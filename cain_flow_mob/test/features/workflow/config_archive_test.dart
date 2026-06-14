import 'package:cain_flow_mob/core/models/workflow_document.dart';
import 'package:cain_flow_mob/core/storage/local_kv_store.dart';
import 'package:cain_flow_mob/features/settings/provider_settings.dart';
import 'package:cain_flow_mob/features/workflow/config_archive.dart';
import 'package:cain_flow_mob/features/workflow/workflow_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  ConfigArchive archiveFor(LocalKvStore store) {
    return ConfigArchive(
      settingsRepository: ProviderSettingsRepository(store: store),
      workflowRepository: WorkflowRepository(store: store),
    );
  }

  test('exports settings and workflows, then re-imports into a fresh store',
      () {
    final source = _MemStore();
    final settings = ProviderSettingsRepository(store: source);
    final workflows = WorkflowRepository(store: source);

    settings.save(
      const ProviderSettings(
        providers: [
          ProviderConfig(
            id: 'p',
            name: 'OpenAI',
            protocol: ModelProtocol.openai,
            apiKey: 'sk-secret',
            endpoint: 'https://api.example.com',
          ),
        ],
        models: [],
        runtime: RuntimeSettings(maxConcurrency: 4),
      ),
    );
    workflows.saveWorkflow(
      'demo',
      WorkflowDocument.empty().copyWith(name: 'Demo'),
    );

    final zip = archiveFor(source).export();
    expect(zip, isNotEmpty);

    // Import into a clean store.
    final target = _MemStore();
    final result = archiveFor(target).import(zip);

    expect(result.settingsImported, isTrue);
    expect(result.workflowsImported, 1);

    final restoredSettings = ProviderSettingsRepository(store: target).load();
    expect(restoredSettings.providers.single.id, 'p');
    expect(restoredSettings.runtime.maxConcurrency, 4);

    final restoredWorkflows = WorkflowRepository(store: target);
    expect(restoredWorkflows.listWorkflowIds(), contains('demo'));
    expect(restoredWorkflows.loadWorkflow('demo')?.name, 'Demo');
  });
}

class _MemStore implements LocalKvStore {
  final Map<String, Object> _v = {};
  @override
  bool containsKey(String key) => _v.containsKey(key);
  @override
  bool getBool(String key, {bool defaultValue = false}) =>
      _v[key] as bool? ?? defaultValue;
  @override
  int getInt(String key, {int defaultValue = 0}) =>
      _v[key] as int? ?? defaultValue;
  @override
  String? getString(String key) => _v[key] as String?;
  @override
  void remove(String key) => _v.remove(key);
  @override
  bool setBool(String key, bool value) {
    _v[key] = value;
    return true;
  }

  @override
  bool setInt(String key, int value) {
    _v[key] = value;
    return true;
  }

  @override
  bool setString(String key, String value) {
    _v[key] = value;
    return true;
  }
}
