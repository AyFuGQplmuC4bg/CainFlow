import 'dart:io';

import 'package:cain_flow_mob/core/models/flow_node.dart';
import 'package:cain_flow_mob/core/network/provider_client.dart';
import 'package:cain_flow_mob/core/storage/local_kv_store.dart';
import 'package:cain_flow_mob/features/execution/cain_flow_node_executor.dart';
import 'package:cain_flow_mob/features/execution/execution_services.dart';
import 'package:cain_flow_mob/features/execution/node_executor.dart';
import 'package:cain_flow_mob/features/execution/provider_request_builder.dart';
import 'package:cain_flow_mob/features/logs/log_signals.dart';
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

      await harness.executor.execute(
        node,
        _context(inputs: {'prompt': 'hi'}),
      );

      final body = harness.client.requests.single.body;
      final messages = body['messages'] as List;
      expect(messages.first, {'role': 'system', 'content': 'be terse'});
      expect(body['temperature'], 0.7);
      expect(body['stream'], false);
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
          FakeResponse(200, '{"data":[{"url":"https://cdn.example.com/a.png"}]}'),
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
      final node = const FlowNode(
        id: 'gen',
        type: 'ImageGenerate',
        x: 0,
        y: 0,
      );

      final result = await harness.executor.execute(
        node,
        _context(inputs: {'prompt': 'a cat'}),
      );

      final image = result.outputs['image'] as Map;
      expect(image['kind'], 'asset');
      expect(image['assetId'], isNotEmpty);
      expect(harness.mediaRepository.loadAll().single.id, image['assetId']);
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
      final urlPayload = {'kind': 'url', 'url': 'https://cdn.example.com/a.png'};

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
        _context(inputs: {
          'image': {'b64_json': _tinyPngBase64, 'mimeType': 'image/png'},
        }),
      );

      final image = result.outputs['image'] as Map;
      expect(image['kind'], 'asset');
      expect(harness.mediaRepository.loadAll().single.id, image['assetId']);
    });
  });
}

/// 1x1 transparent PNG.
const _tinyPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==';

/// Shared test harness reused across Text/TextChat/ImageGenerate/ImageSave.
class ExecutorHarness {
  ExecutorHarness({
    ProviderSettings? settings,
    List<FakeResponse> responses = const [],
  }) : client = FakeProviderClient(responses) {
    store = MemoryLocalKvStore();
    settingsRepository = ProviderSettingsRepository(store: store);
    if (settings != null) settingsRepository.save(settings);
    logs = LogSignals();
    mediaRoot = Directory.systemTemp.createTempSync('cainflow_exec_test');
    mediaRepository = MediaRepository(store: store, mediaRoot: mediaRoot);
    services = ExecutionServices(
      settingsRepository: settingsRepository,
      providerClient: client,
      mediaRepository: mediaRepository,
      logs: logs,
      workflowId: 'wf-test',
    );
    executor = CainFlowNodeExecutor(services: services);
  }

  late final MemoryLocalKvStore store;
  late final ProviderSettingsRepository settingsRepository;
  late final LogSignals logs;
  late final Directory mediaRoot;
  late final MediaRepository mediaRepository;
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
  int _index = 0;

  @override
  Future<ProviderResponse> send(
    ProviderRequest request, {
    ProviderRequestOptions options = const ProviderRequestOptions(),
  }) async {
    requests.add(request);
    final response = _responses[_index.clamp(0, _responses.length - 1)];
    if (_index < _responses.length - 1) _index += 1;
    return ProviderResponse(statusCode: response.statusCode, body: response.body);
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
