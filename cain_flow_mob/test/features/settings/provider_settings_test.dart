import 'package:cain_flow_mob/core/storage/local_kv_store.dart';
import 'package:cain_flow_mob/features/settings/provider_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'provider settings repository saves and restores providers and models',
    () {
      final store = _MemoryLocalKvStore();
      final repository = ProviderSettingsRepository(store: store);
      final settings = ProviderSettings(
        providers: const [
          ProviderConfig(
            id: 'prov_openai',
            name: 'OpenAI compatible',
            protocol: ModelProtocol.openai,
            apiKey: 'sk-secret',
            endpoint: 'https://api.example.com',
          ),
        ],
        models: const [
          ModelConfig(
            id: 'model_chat',
            name: 'Chat',
            modelId: 'gpt-4.1',
            taskType: ModelTaskType.chat,
            protocol: ModelProtocol.openai,
            providerIds: ['prov_openai'],
          ),
        ],
        runtime: const RuntimeSettings(
          requestTimeoutSeconds: 45,
          retryCount: 2,
          activeChatModelId: 'model_chat',
          activeImageModelId: 'model_image',
        ),
      );

      repository.save(settings);
      final restored = repository.load();

      expect(restored.providers.single.endpoint, 'https://api.example.com');
      expect(restored.providers.single.maskedApiKey, 'sk-...cret');
      expect(restored.models.single.modelId, 'gpt-4.1');
      expect(restored.runtime.requestTimeoutSeconds, 45);
      expect(restored.runtime.retryCount, 2);
      expect(restored.runtime.activeChatModelId, 'model_chat');
      expect(restored.runtime.activeImageModelId, 'model_image');
    },
  );

  test('provider settings load runtime defaults from legacy json', () {
    final settings = ProviderSettings.fromJson(const {
      'providers': <Map<String, dynamic>>[],
      'models': <Map<String, dynamic>>[],
    });

    expect(settings.runtime.requestTimeoutSeconds, 60);
    expect(settings.runtime.retryCount, 0);
    expect(settings.runtime.activeChatModelId, '');
    expect(settings.runtime.activeImageModelId, '');
  });
}

class _MemoryLocalKvStore implements LocalKvStore {
  final Map<String, Object> _values = {};

  @override
  bool containsKey(String key) => _values.containsKey(key);

  @override
  bool getBool(String key, {bool defaultValue = false}) {
    return _values[key] as bool? ?? defaultValue;
  }

  @override
  int getInt(String key, {int defaultValue = 0}) {
    return _values[key] as int? ?? defaultValue;
  }

  @override
  String? getString(String key) => _values[key] as String?;

  @override
  void remove(String key) {
    _values.remove(key);
  }

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
