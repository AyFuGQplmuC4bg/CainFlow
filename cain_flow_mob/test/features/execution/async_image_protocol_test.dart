import 'package:cain_flow_mob/features/execution/async_image_protocol.dart';
import 'package:cain_flow_mob/features/settings/provider_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const provider = ProviderConfig(
    id: 'p',
    name: 'Async',
    protocol: ModelProtocol.newApiImageAsync,
    apiKey: 'sk-secret',
    endpoint: 'https://api.example.com',
  );
  const model = ModelConfig(
    id: 'm',
    name: 'AsyncImage',
    modelId: 'flux-async',
    taskType: ModelTaskType.image,
    protocol: ModelProtocol.newApiImageAsync,
    providerIds: ['p'],
  );

  group('request building', () {
    test('submit targets the images generations path with auth header', () {
      final req = AsyncImageProtocol.buildSubmitRequest(
        provider: provider,
        model: model,
        prompt: 'a fox',
        size: '1024x1024',
      );
      expect(req.method, 'POST');
      expect(req.url, 'https://api.example.com/v1/images/generations');
      expect(req.headers['Authorization'], 'Bearer sk-secret');
      expect(req.body['prompt'], 'a fox');
      expect(req.body['size'], '1024x1024');
    });

    test('poll appends the task id', () {
      final req =
          AsyncImageProtocol.buildPollRequest(provider: provider, taskId: 't123');
      expect(req.method, 'GET');
      expect(req.url, 'https://api.example.com/v1/images/generations/t123');
    });
  });

  group('extractors', () {
    test('task id from common field shapes', () {
      expect(AsyncImageProtocol.extractTaskId({'id': 'a'}), 'a');
      expect(AsyncImageProtocol.extractTaskId({'task_id': 'b'}), 'b');
      expect(
        AsyncImageProtocol.extractTaskId({
          'data': {'id': 'c'},
        }),
        'c',
      );
    });

    test('status normalization', () {
      expect(
        AsyncImageProtocol.extractStatus({'status': 'succeeded'}),
        AsyncImageStatus.completed,
      );
      expect(
        AsyncImageProtocol.extractStatus({'status': 'failed'}),
        AsyncImageStatus.failed,
      );
      expect(
        AsyncImageProtocol.extractStatus({'status': 'running'}),
        AsyncImageStatus.pending,
      );
      expect(
        AsyncImageProtocol.extractStatus(const {}),
        AsyncImageStatus.pending,
      );
    });

    test('result url from nested data and list fields', () {
      expect(
        AsyncImageProtocol.extractResultUrl({
          'data': {'image_url': 'https://x/a.png'},
        }),
        'https://x/a.png',
      );
      expect(
        AsyncImageProtocol.extractResultUrl({
          'data': {
            'result_urls': ['https://x/b.png'],
          },
        }),
        'https://x/b.png',
      );
    });
  });
}
