import 'package:cain_flow_mob/core/network/provider_client.dart';
import 'package:cain_flow_mob/core/storage/local_kv_store.dart';
import 'package:cain_flow_mob/features/execution/execution_services.dart';
import 'package:cain_flow_mob/features/execution/provider_request_builder.dart';
import 'package:cain_flow_mob/features/logs/log_signals.dart';
import 'package:cain_flow_mob/features/media/media_repository.dart';
import 'package:cain_flow_mob/features/settings/provider_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ExecutionServices exposes runtime collaborators and copyWith', () {
    final store = _MemoryLocalKvStore();
    final services = ExecutionServices(
      settingsRepository: ProviderSettingsRepository(store: store),
      providerClient: _NoopProviderClient(),
      mediaRepository: MediaRepository(store: store),
      logs: LogSignals(),
    );

    expect(services.workflowId, '');
    final scoped = services.copyWith(workflowId: 'wf-1');
    expect(scoped.workflowId, 'wf-1');
    // Collaborators are shared, not rebuilt.
    expect(scoped.settingsRepository, same(services.settingsRepository));
    expect(scoped.providerClient, same(services.providerClient));
    expect(scoped.mediaRepository, same(services.mediaRepository));
    expect(scoped.logs, same(services.logs));
  });
}

class _NoopProviderClient implements ProviderClient {
  @override
  Future<ProviderResponse> send(
    ProviderRequest request, {
    ProviderRequestOptions options = const ProviderRequestOptions(),
  }) async {
    return const ProviderResponse(statusCode: 200, body: '{}');
  }
}

class _MemoryLocalKvStore implements LocalKvStore {
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
