import 'dart:convert';
import 'dart:io';

import 'package:cain_flow_mob/core/models/flow_node.dart';
import 'package:cain_flow_mob/core/models/workflow_document.dart';
import 'package:cain_flow_mob/core/network/provider_client.dart';
import 'package:cain_flow_mob/core/storage/local_kv_store.dart';
import 'package:cain_flow_mob/features/background/background_execution_coordinator.dart';
import 'package:cain_flow_mob/features/background/background_job_repository.dart';
import 'package:cain_flow_mob/features/execution/cain_flow_node_executor.dart';
import 'package:cain_flow_mob/features/execution/execution_services.dart';
import 'package:cain_flow_mob/features/execution/execution_signals.dart';
import 'package:cain_flow_mob/features/execution/node_executor.dart';
import 'package:cain_flow_mob/features/execution/provider_request_builder.dart';
import 'package:cain_flow_mob/features/logs/log_signals.dart';
import 'package:cain_flow_mob/features/media/media_downloader.dart';
import 'package:cain_flow_mob/features/media/media_repository.dart';
import 'package:cain_flow_mob/features/settings/provider_settings.dart';
import 'package:flutter_test/flutter_test.dart';

NodeExecutionContext _context({Map<String, dynamic> inputs = const {}}) {
  return NodeExecutionContext(
    inputs: inputs,
    previousResults: const {},
    isCanceled: () => false,
  );
}

void main() {
  group('Text node', () {
    test('reads text from node data', () async {
      final harness = ExecutorHarness();
      final node = const FlowNode(
        id: 'n1',
        type: 'Text',
        x: 0,
        y: 0,
        data: {'text': 'hello from data'},
      );

      final result = await harness.executor.execute(node, _context());

      expect(result.outputs['text'], 'hello from data');
    });

    test('falls back to legacy top-level extra text', () async {
      final harness = ExecutorHarness();
      final node = FlowNode.fromJson(const {
        'id': 'n1',
        'type': 'Text',
        'x': 0,
        'y': 0,
        'text': 'legacy top level',
      });

      final result = await harness.executor.execute(node, _context());

      expect(result.outputs['text'], 'legacy top level');
    });

    test('produces empty text without network', () async {
      final harness = ExecutorHarness();
      final node = const FlowNode(id: 'n1', type: 'Text', x: 0, y: 0);

      final result = await harness.executor.execute(node, _context());

      expect(result.outputs['text'], '');
      expect(harness.client.requests, isEmpty);
    });
  });

  group('TextChat node', () {
    ProviderSettings chatSettings() {
      return const ProviderSettings(
        providers: [
          ProviderConfig(
            id: 'prov',
            name: 'OpenAI',
            protocol: ModelProtocol.openai,
            apiKey: 'sk-secret',
            endpoint: 'https://api.example.com',
          ),
        ],
        models: [
          ModelConfig(
            id: 'chat',
            name: 'Chat',
            modelId: 'gpt-4.1',
            taskType: ModelTaskType.chat,
            protocol: ModelProtocol.openai,
            providerIds: ['prov'],
          ),
        ],
        runtime: RuntimeSettings(activeChatModelId: 'chat'),
      );
    }

    test('runs Text -> TextChat and parses OpenAI content', () async {
      final harness = ExecutorHarness(
        settings: chatSettings(),
        responses: const [
          FakeResponse(
            200,
            '{"choices":[{"message":{"role":"assistant","content":"hi there"}}]}',
          ),
        ],
      );
      final node = const FlowNode(id: 'chatNode', type: 'TextChat', x: 0, y: 0);

      final result = await harness.executor.execute(
        node,
        _context(inputs: {'prompt': 'say hi'}),
      );

      expect(result.outputs['text'], 'hi there');
      expect(harness.client.requests.single.body['messages'], isA<List>());
      expect(
        harness.logs.entries.value.any((e) => e.message.contains('succeeded')),
        isTrue,
      );
    });

    test('parses Gemini candidate text', () async {
      final harness = ExecutorHarness(
        settings: const ProviderSettings(
          providers: [
            ProviderConfig(
              id: 'g',
              name: 'Google',
              protocol: ModelProtocol.google,
              apiKey: 'key',
              endpoint: 'https://generativelanguage.googleapis.com',
            ),
          ],
          models: [
            ModelConfig(
              id: 'gchat',
              name: 'Gemini',
              modelId: 'gemini-2.0',
              taskType: ModelTaskType.chat,
              protocol: ModelProtocol.google,
              providerIds: ['g'],
            ),
          ],
          runtime: RuntimeSettings(activeChatModelId: 'gchat'),
        ),
        responses: const [
          FakeResponse(
            200,
            '{"candidates":[{"content":{"parts":[{"text":"hello "},{"text":"world"}]}}]}',
          ),
        ],
      );
      final node = const FlowNode(id: 'c', type: 'TextChat', x: 0, y: 0);

      final result = await harness.executor.execute(
        node,
        _context(inputs: {'prompt': 'hi'}),
      );

      expect(result.outputs['text'], 'hello world');
    });

    test('logs and throws on provider failure', () async {
      final harness = ExecutorHarness(
        settings: chatSettings(),
        responses: const [FakeResponse(401, 'unauthorized')],
      );
      final node = const FlowNode(id: 'c', type: 'TextChat', x: 0, y: 0);

      await expectLater(
        harness.executor.execute(node, _context(inputs: {'prompt': 'hi'})),
        throwsA(isA<Object>()),
      );
      expect(harness.logs.hasErrors.value, isTrue);
    });

    test('forwards system prompt and coerced custom params', () async {
      final harness = ExecutorHarness(
        settings: chatSettings(),
        responses: const [
          FakeResponse(200, '{"choices":[{"message":{"content":"ok"}}]}'),
        ],
      );
      final node = const FlowNode(
        id: 'chatNode',
        type: 'TextChat',
        x: 0,
        y: 0,
        data: {
          'systemPrompt': 'be terse',
          'customParams': {'temperature': '0.7', 'stream': 'false'},
        },
      );

      await harness.executor.execute(node, _context(inputs: {'prompt': 'hi'}));

      final body = harness.client.requests.single.body;
      final messages = body['messages'] as List;
      expect(messages.first, {'role': 'system', 'content': 'be terse'});
      expect(body['temperature'], 0.7);
      expect(body['stream'], false);
    });

    test(
      'injects a url reference image as a multimodal content part',
      () async {
        final harness = ExecutorHarness(
          settings: chatSettings(),
          responses: const [
            FakeResponse(200, '{"choices":[{"message":{"content":"ok"}}]}'),
          ],
        );
        final node = const FlowNode(id: 'c', type: 'TextChat', x: 0, y: 0);

        await harness.executor.execute(
          node,
          _context(
            inputs: {
              'prompt': 'describe',
              'image_1': {'kind': 'url', 'url': 'https://cdn/x.png'},
            },
          ),
        );

        final messages =
            harness.client.requests.single.body['messages'] as List;
        final userContent = (messages.last as Map)['content'] as List;
        expect(userContent.first, {'type': 'text', 'text': 'describe'});
        expect(
          userContent.any(
            (p) =>
                p is Map &&
                p['type'] == 'image_url' &&
                (p['image_url'] as Map)['url'] == 'https://cdn/x.png',
          ),
          isTrue,
        );
      },
    );

    test('accumulates an SSE streaming response into the final text', () async {
      final harness = ExecutorHarness(
        settings: chatSettings(),
        responses: const [
          FakeResponse(
            200,
            'data: {"choices":[{"delta":{"content":"Hel"}}]}\n'
            'data: {"choices":[{"delta":{"content":"lo"}}]}\n'
            'data: [DONE]\n',
          ),
        ],
      );
      final node = const FlowNode(
        id: 'c',
        type: 'TextChat',
        x: 0,
        y: 0,
        data: {'stream': 'true'},
      );

      final result = await harness.executor.execute(
        node,
        _context(inputs: {'prompt': 'hi'}),
      );

      expect(result.outputs['text'], 'Hello');
      expect(harness.client.requests.single.body['stream'], true);
    });
  });

  group('ImageGenerate node', () {
    ProviderSettings imageSettings() {
      return const ProviderSettings(
        providers: [
          ProviderConfig(
            id: 'prov',
            name: 'OpenAI',
            protocol: ModelProtocol.openai,
            apiKey: 'sk-secret',
            endpoint: 'https://api.example.com',
          ),
        ],
        models: [
          ModelConfig(
            id: 'img',
            name: 'Image',
            modelId: 'gpt-image-1',
            taskType: ModelTaskType.image,
            protocol: ModelProtocol.openai,
            providerIds: ['prov'],
          ),
        ],
        runtime: RuntimeSettings(activeImageModelId: 'img'),
      );
    }

    test('returns URL metadata without downloading', () async {
      final harness = ExecutorHarness(
        settings: imageSettings(),
        responses: const [
          FakeResponse(
            200,
            '{"data":[{"url":"https://cdn.example.com/a.png"}]}',
          ),
        ],
      );
      final node = const FlowNode(id: 'gen', type: 'ImageGenerate', x: 0, y: 0);

      final result = await harness.executor.execute(
        node,
        _context(inputs: {'prompt': 'a cat'}),
      );

      final image = result.outputs['image'] as Map;
      expect(image['kind'], 'url');
      expect(image['url'], 'https://cdn.example.com/a.png');
    });

    test('saves base64 image as a local media asset', () async {
      final harness = ExecutorHarness(
        settings: imageSettings(),
        responses: [
          FakeResponse(200, '{"data":[{"b64_json":"$_tinyPngBase64"}]}'),
        ],
      );
      final node = const FlowNode(id: 'gen', type: 'ImageGenerate', x: 0, y: 0);

      final result = await harness.executor.execute(
        node,
        _context(inputs: {'prompt': 'a cat'}),
      );

      final image = result.outputs['image'] as Map;
      expect(image['kind'], 'asset');
      expect(image['assetId'], isNotEmpty);
      expect(harness.mediaRepository.loadAll().single.id, image['assetId']);
    });

    test('combines connected system and camera prompts into the image prompt', () async {
      final harness = ExecutorHarness(
        settings: imageSettings(),
        responses: const [
          FakeResponse(
            200,
            '{"data":[{"url":"https://cdn.example.com/a.png"}]}',
          ),
        ],
      );
      final node = const FlowNode(id: 'gen', type: 'ImageGenerate', x: 0, y: 0);

      await harness.executor.execute(
        node,
        _context(
          inputs: {
            'prompt': 'a desk lamp',
            'system_prompt': 'keep it minimal',
            'camera_prompt': 'three-quarter product shot',
          },
        ),
      );

      expect(
        harness.client.requests.single.body['prompt'],
        'a desk lamp\n\n'
        'System instruction:\nkeep it minimal\n\n'
        'Camera composition instruction:\nthree-quarter product shot',
      );
    });

    test('sends reference images, mask, and generation count', () async {
      final harness = ExecutorHarness(
        settings: imageSettings(),
        responses: const [
          FakeResponse(
            200,
            '{"data":[{"url":"https://cdn.example.com/a.png"},{"url":"https://cdn.example.com/b.png"}]}',
          ),
        ],
      );
      final node = const FlowNode(
        id: 'gen',
        type: 'ImageGenerate',
        x: 0,
        y: 0,
        data: {
          'generationCount': 2,
          'moderation': 'auto',
          'background': 'transparent',
        },
      );

      final result = await harness.executor.execute(
        node,
        _context(
          inputs: {
            'prompt': 'a cat',
            'image_1': {
              'kind': 'url',
              'url': 'https://cdn.example.com/ref.png',
            },
            'mask': {'kind': 'url', 'url': 'https://cdn.example.com/mask.png'},
          },
        ),
      );

      final body = harness.client.requests.single.body;
      expect(
        harness.client.requests.single.url,
        'https://api.example.com/v1/images/edits',
      );
      expect(body['reference_images'], ['https://cdn.example.com/ref.png']);
      expect(body['mask'], 'https://cdn.example.com/mask.png');
      expect(body['n'], 2);
      expect(body['moderation'], 'auto');
      expect(body['background'], 'transparent');

      final image = result.outputs['image'] as Map;
      expect(image['kind'], 'images');
      expect(image['count'], 2);
      expect((image['items'] as List).length, 2);
    });
  });

  group('ImageGenerate async (newApiImageAsync)', () {
    ProviderSettings asyncSettings({int pollInterval = 1, int timeout = 30}) {
      return ProviderSettings(
        providers: const [
          ProviderConfig(
            id: 'prov',
            name: 'Async',
            protocol: ModelProtocol.newApiImageAsync,
            apiKey: 'sk-secret',
            endpoint: 'https://api.example.com',
          ),
        ],
        models: const [
          ModelConfig(
            id: 'aimg',
            name: 'AsyncImage',
            modelId: 'flux-async',
            taskType: ModelTaskType.image,
            protocol: ModelProtocol.newApiImageAsync,
            providerIds: ['prov'],
          ),
        ],
        runtime: RuntimeSettings(
          requestTimeoutSeconds: timeout,
          activeImageModelId: 'aimg',
          asyncPollIntervalSeconds: pollInterval,
          asyncTimeoutSeconds: timeout,
        ),
      );
    }

    test(
      'submits, polls until completed, and returns the result URL',
      () async {
        final harness = ExecutorHarness(
          settings: asyncSettings(),
          responses: const [
            FakeResponse(200, '{"id":"task-1"}'), // submit
            FakeResponse(200, '{"status":"pending"}'), // poll 1
            FakeResponse(
              200,
              '{"status":"completed","data":{"image_url":"https://cdn/x.png"}}',
            ), // poll 2
          ],
        );
        final node = const FlowNode(
          id: 'gen',
          type: 'ImageGenerate',
          x: 0,
          y: 0,
        );

        final result = await harness.executor.execute(
          node,
          _context(inputs: {'prompt': 'a city'}),
        );

        final image = result.outputs['image'] as Map;
        expect(image['kind'], 'url');
        expect(image['url'], 'https://cdn/x.png');
        // 1 submit + 2 polls.
        expect(harness.client.requests.length, 3);
      },
    );

    test('propagates request timeout to submit and poll requests', () async {
      final harness = ExecutorHarness(
        settings: asyncSettings(timeout: 45),
        responses: const [
          FakeResponse(200, '{"id":"task-timeout"}'),
          FakeResponse(
            200,
            '{"status":"completed","data":{"image_url":"https://cdn/x.png"}}',
          ),
        ],
      );
      final node = const FlowNode(id: 'gen', type: 'ImageGenerate', x: 0, y: 0);

      await harness.executor.execute(
        node,
        _context(inputs: const {'prompt': 'a city'}),
      );

      expect(harness.client.options.length, 2);
      expect(harness.client.options.first.timeout, const Duration(seconds: 45));
      expect(harness.client.options.last.timeout, const Duration(seconds: 45));
    });

    test('resumes from a persisted async task without resubmitting', () async {
      final harness = ExecutorHarness(
        settings: asyncSettings(),
        responses: const [
          FakeResponse(
            200,
            '{"status":"completed","data":{"image_url":"https://cdn/resume.png"}}',
          ),
        ],
        backgroundJobId: 'job-resume',
      );
      harness.backgroundCoordinator.enqueueWorkflow(
        jobId: 'job-resume',
        workflow: _workflowForAsyncNode(),
        asyncTask: BackgroundAsyncTaskMetadata(
          taskId: 'task-resume',
          provider: 'prov',
          pollUrl: 'https://api.example.com/v1/images/generations/task-resume',
          state: 'submitted',
          nodeId: 'gen',
          pollAttempts: 1,
          nextPollAt: DateTime.now()
              .subtract(const Duration(milliseconds: 1))
              .toUtc()
              .toIso8601String(),
          deadlineAt: DateTime.now()
              .add(const Duration(minutes: 5))
              .toUtc()
              .toIso8601String(),
        ),
      );

      final node = const FlowNode(id: 'gen', type: 'ImageGenerate', x: 0, y: 0);
      final result = await harness.executor.execute(
        node,
        _context(inputs: const {'prompt': 'resume me'}),
      );

      final image = result.outputs['image'] as Map;
      expect(image['url'], 'https://cdn/resume.png');
      expect(harness.client.requests.length, 1);
      expect(harness.client.requests.single.method, 'GET');

      final snapshot = harness.backgroundCoordinator.loadJob('job-resume');
      expect(snapshot, isNotNull);
      expect(snapshot!.asyncTask, isNotNull);
      expect(snapshot.asyncTask!.taskId, 'task-resume');
      expect(snapshot.asyncTask!.state, 'completed');
      expect(snapshot.asyncTask!.pollAttempts, 2);
    });

    test('throws when the task reports failure', () async {
      final harness = ExecutorHarness(
        settings: asyncSettings(),
        responses: const [
          FakeResponse(200, '{"id":"task-2"}'),
          FakeResponse(200, '{"status":"failed"}'),
        ],
      );
      final node = const FlowNode(id: 'gen', type: 'ImageGenerate', x: 0, y: 0);

      await expectLater(
        harness.executor.execute(node, _context(inputs: {'prompt': 'x'})),
        throwsA(isA<StateError>()),
      );
    });

    test('stops polling when canceled', () async {
      var canceled = false;
      final harness = ExecutorHarness(
        settings: asyncSettings(),
        responses: const [
          FakeResponse(200, '{"id":"task-3"}'),
          FakeResponse(200, '{"status":"pending"}'),
        ],
      );
      final node = const FlowNode(id: 'gen', type: 'ImageGenerate', x: 0, y: 0);
      final context = NodeExecutionContext(
        inputs: const {'prompt': 'x'},
        previousResults: const {},
        isCanceled: () => canceled,
      );

      // Cancel shortly after submission.
      Future<void>.delayed(
        const Duration(milliseconds: 400),
        () => canceled = true,
      );

      await expectLater(
        harness.executor.execute(node, context),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('ImageImport node', () {
    test('resolves a stored asset id into a passthrough payload', () async {
      final harness = ExecutorHarness();
      final asset = await harness.mediaRepository.saveBytes(
        workflowId: 'wf-test',
        fileName: 'pic.png',
        mimeType: 'image/png',
        bytes: base64Decode(_tinyPngBase64),
      );
      final node = FlowNode(
        id: 'imp',
        type: 'ImageImport',
        x: 0,
        y: 0,
        data: {'assetId': asset.id},
      );

      final result = await harness.executor.execute(node, _context());

      final image = result.outputs['image'] as Map;
      expect(image['kind'], 'asset');
      expect(image['assetId'], asset.id);
    });

    test('throws when no image has been selected', () async {
      final harness = ExecutorHarness();
      final node = const FlowNode(id: 'imp', type: 'ImageImport', x: 0, y: 0);
      await expectLater(
        harness.executor.execute(node, _context()),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('ImagePreview node', () {
    test('passes its input image through to its output', () async {
      final harness = ExecutorHarness();
      final node = const FlowNode(id: 'prev', type: 'ImagePreview', x: 0, y: 0);
      final payload = {'kind': 'url', 'url': 'https://cdn.example.com/a.png'};

      final result = await harness.executor.execute(
        node,
        _context(inputs: {'image': payload}),
      );

      expect(result.outputs['image'], payload);
    });

    test('produces no output when no image is connected', () async {
      final harness = ExecutorHarness();
      final node = const FlowNode(id: 'prev', type: 'ImagePreview', x: 0, y: 0);
      final result = await harness.executor.execute(node, _context());
      expect(result.outputs.containsKey('image'), isFalse);
    });
  });

  group('ImageSave node', () {
    test('passes through an existing local asset payload', () async {
      final harness = ExecutorHarness();
      final node = const FlowNode(id: 'save', type: 'ImageSave', x: 0, y: 0);
      final assetPayload = {
        'kind': 'asset',
        'assetId': 'a1',
        'relativePath': 'workflows/wf/media/a1.png',
        'mimeType': 'image/png',
        'byteLength': 10,
      };

      final result = await harness.executor.execute(
        node,
        _context(inputs: {'image': assetPayload}),
      );

      expect(result.outputs['image'], assetPayload);
    });

    test('keeps URL metadata without downloading', () async {
      final harness = ExecutorHarness();
      final node = const FlowNode(id: 'save', type: 'ImageSave', x: 0, y: 0);
      final urlPayload = {
        'kind': 'url',
        'url': 'https://cdn.example.com/a.png',
      };

      final result = await harness.executor.execute(
        node,
        _context(inputs: {'image': urlPayload}),
      );

      expect(result.outputs['image'], urlPayload);
    });

    test('saves base64 bytes through MediaRepository', () async {
      final harness = ExecutorHarness();
      final node = const FlowNode(id: 'save', type: 'ImageSave', x: 0, y: 0);

      final result = await harness.executor.execute(
        node,
        _context(
          inputs: {
            'image': {'b64_json': _tinyPngBase64, 'mimeType': 'image/png'},
          },
        ),
      );

      final image = result.outputs['image'] as Map;
      expect(image['kind'], 'asset');
      expect(harness.mediaRepository.loadAll().single.id, image['assetId']);
    });

    test('downloads a remote URL to a local asset when opted in', () async {
      final harness = ExecutorHarness(downloader: _FakeDownloader());
      final node = const FlowNode(
        id: 'save',
        type: 'ImageSave',
        x: 0,
        y: 0,
        data: {'downloadRemote': 'true'},
      );

      final result = await harness.executor.execute(
        node,
        _context(
          inputs: {
            'image': {'kind': 'url', 'url': 'https://cdn/remote.png'},
          },
        ),
      );

      final image = result.outputs['image'] as Map;
      expect(image['kind'], 'asset');
      expect(harness.mediaRepository.loadAll().single.id, image['assetId']);
    });

    test('keeps URL metadata when download is not requested', () async {
      final harness = ExecutorHarness(downloader: _FakeDownloader());
      final node = const FlowNode(id: 'save', type: 'ImageSave', x: 0, y: 0);

      final result = await harness.executor.execute(
        node,
        _context(
          inputs: {
            'image': {'kind': 'url', 'url': 'https://cdn/remote.png'},
          },
        ),
      );

      expect((result.outputs['image'] as Map)['kind'], 'url');
    });
  });
}

class _FakeDownloader implements MediaDownloader {
  @override
  Future<DownloadedMedia> download(
    String url, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    return DownloadedMedia(
      bytes: base64Decode(_tinyPngBase64),
      mimeType: 'image/png',
    );
  }
}

/// 1x1 transparent PNG.
const _tinyPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

WorkflowDocument _workflowForAsyncNode() {
  return const WorkflowDocument(
    name: 'Async workflow',
    canvas: WorkflowCanvas(x: 0, y: 0, zoom: 1),
    nodes: [FlowNode(id: 'gen', type: 'ImageGenerate', x: 0, y: 0)],
    connections: [],
    version: WorkflowDocument.defaultVersion,
  );
}

/// Shared test harness reused across Text/TextChat/ImageGenerate/ImageSave.
class ExecutorHarness {
  ExecutorHarness({
    ProviderSettings? settings,
    List<FakeResponse> responses = const [],
    MediaDownloader? downloader,
    String backgroundJobId = '',
  }) : client = FakeProviderClient(responses) {
    store = MemoryLocalKvStore();
    settingsRepository = ProviderSettingsRepository(store: store);
    if (settings != null) settingsRepository.save(settings);
    logs = LogSignals();
    executionSignals = ExecutionSignals();
    backgroundCoordinator = BackgroundExecutionCoordinator(
      repository: BackgroundJobRepository(store: store),
    );
    executionSignals.backgroundJobId.value = backgroundJobId;
    mediaRoot = Directory.systemTemp.createTempSync('cainflow_exec_test');
    mediaRepository = MediaRepository(store: store, mediaRoot: mediaRoot);
    services = ExecutionServices(
      settingsRepository: settingsRepository,
      providerClient: client,
      mediaRepository: mediaRepository,
      logs: logs,
      workflowId: 'wf-test',
      backgroundJobId: backgroundJobId,
      downloaderOverride: downloader,
      executionSignals: executionSignals,
      backgroundCoordinator: backgroundCoordinator,
    );
    executor = CainFlowNodeExecutor(services: services);
  }

  late final MemoryLocalKvStore store;
  late final ProviderSettingsRepository settingsRepository;
  late final LogSignals logs;
  late final ExecutionSignals executionSignals;
  late final Directory mediaRoot;
  late final MediaRepository mediaRepository;
  late final BackgroundExecutionCoordinator backgroundCoordinator;
  late final ExecutionServices services;
  late final CainFlowNodeExecutor executor;
  final FakeProviderClient client;
}

class FakeResponse {
  const FakeResponse(this.statusCode, this.body);
  final int statusCode;
  final String body;
}

class FakeProviderClient implements ProviderClient {
  FakeProviderClient(this._responses);

  final List<FakeResponse> _responses;
  final List<ProviderRequest> requests = [];
  final List<ProviderRequestOptions> options = [];
  int _index = 0;

  @override
  Future<ProviderResponse> send(
    ProviderRequest request, {
    ProviderRequestOptions options = const ProviderRequestOptions(),
  }) async {
    requests.add(request);
    this.options.add(options);
    final response = _responses[_index.clamp(0, _responses.length - 1)];
    if (_index < _responses.length - 1) _index += 1;
    return ProviderResponse(
      statusCode: response.statusCode,
      body: response.body,
    );
  }
}

class MemoryLocalKvStore implements LocalKvStore {
  final Map<String, Object> _values = {};

  @override
  bool containsKey(String key) => _values.containsKey(key);

  @override
  bool getBool(String key, {bool defaultValue = false}) =>
      _values[key] as bool? ?? defaultValue;

  @override
  int getInt(String key, {int defaultValue = 0}) =>
      _values[key] as int? ?? defaultValue;

  @override
  String? getString(String key) => _values[key] as String?;

  @override
  void remove(String key) => _values.remove(key);

  @override
  bool setBool(String key, bool value) {
    _values[key] = value;
    return true;
  }

  @override
  bool setInt(String key, int value) {
    _values[key] = value;
    return true;
  }

  @override
  bool setString(String key, String value) {
    _values[key] = value;
    return true;
  }
}
