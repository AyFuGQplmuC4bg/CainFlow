import 'package:cain_flow_mob/core/storage/local_kv_store.dart';
import 'package:cain_flow_mob/features/logs/log_signals.dart';
import 'package:cain_flow_mob/features/settings/provider_settings.dart';
import 'package:cain_flow_mob/features/settings/settings_screen.dart';
import 'package:cain_flow_mob/features/workbench/workbench_signals.dart';
import 'package:cain_flow_mob/features/workflow/workflow_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('settings screen renders providers and export actions', (
    tester,
  ) async {
    final store = _MemoryLocalKvStore();
    final repository = ProviderSettingsRepository(store: store);
    repository.save(
      const ProviderSettings(
        providers: [
          ProviderConfig(
            id: 'prov',
            name: 'Provider',
            protocol: ModelProtocol.openai,
            apiKey: 'sk-secret',
            endpoint: 'https://api.example.com',
          ),
        ],
        models: [
          ModelConfig(
            id: 'model',
            name: 'Chat',
            modelId: 'gpt-4.1',
            taskType: ModelTaskType.chat,
            protocol: ModelProtocol.openai,
            providerIds: ['prov'],
          ),
        ],
      ),
    );
    final logs = LogSignals();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsScreen(repository: repository, logs: logs),
        ),
      ),
    );

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Provider'), findsOneWidget);
    expect(find.text('Chat'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Export graph'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(find.text('Export graph'));
    await tester.pump();
    await tester.tap(find.text('Export graph'));
    await tester.pump();

    expect(find.textContaining('"name": "Untitled Workflow"'), findsOneWidget);
    expect(logs.entries.value.single.message, 'Workflow graph exported');
  });

  testWidgets('settings screen can add and save a provider', (tester) async {
    final store = _MemoryLocalKvStore();
    final repository = ProviderSettingsRepository(store: store);
    final logs = LogSignals();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsScreen(repository: repository, logs: logs),
        ),
      ),
    );

    await tester.tap(find.text('Add provider'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('provider-name-field')),
      'My Provider',
    );
    await tester.enterText(
      find.byKey(const Key('provider-endpoint-field')),
      'https://api.example.com',
    );
    await tester.enterText(
      find.byKey(const Key('provider-apikey-field')),
      'sk-secret-value',
    );

    await tester.tap(find.byKey(const Key('provider-save-button')));
    await tester.pumpAndSettle();

    final saved = repository.load();
    expect(saved.providers.single.name, 'My Provider');
    expect(saved.providers.single.endpoint, 'https://api.example.com');
    expect(saved.providers.single.apiKey, 'sk-secret-value');
    expect(find.text('My Provider'), findsOneWidget);
    // API key is masked in the read-only summary.
    expect(find.textContaining('sk-secret-value'), findsNothing);
  });

  testWidgets('settings screen can add and save a model', (tester) async {
    final store = _MemoryLocalKvStore();
    final repository = ProviderSettingsRepository(store: store);
    repository.save(
      const ProviderSettings(
        providers: [
          ProviderConfig(
            id: 'prov',
            name: 'Provider',
            protocol: ModelProtocol.openai,
            apiKey: 'sk-secret',
            endpoint: 'https://api.example.com',
          ),
        ],
        models: [],
      ),
    );
    final logs = LogSignals();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsScreen(repository: repository, logs: logs),
        ),
      ),
    );

    await tester.tap(find.text('Add model'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('model-name-field')),
      'My Chat Model',
    );
    await tester.enterText(find.byKey(const Key('model-id-field')), 'gpt-4.1');

    await tester.tap(find.byKey(const Key('model-save-button')));
    await tester.pumpAndSettle();

    final saved = repository.load();
    expect(saved.models.single.name, 'My Chat Model');
    expect(saved.models.single.modelId, 'gpt-4.1');
    expect(saved.models.single.taskType, ModelTaskType.chat);
  });

  testWidgets('model dialog saves multiple selected providers', (tester) async {
    final store = _MemoryLocalKvStore();
    final repository = ProviderSettingsRepository(store: store);
    repository.save(
      const ProviderSettings(
        providers: [
          ProviderConfig(
            id: 'prov_fast',
            name: 'Fast Provider',
            protocol: ModelProtocol.openai,
            apiKey: 'sk-fast',
            endpoint: 'https://fast.example.com',
          ),
          ProviderConfig(
            id: 'prov_slow',
            name: 'Slow Provider',
            protocol: ModelProtocol.openai,
            apiKey: 'sk-slow',
            endpoint: 'https://slow.example.com',
          ),
        ],
        models: [],
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SettingsScreen(repository: repository)),
      ),
    );

    await tester.tap(find.text('Add model'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('model-name-field')), 'Chat');
    await tester.enterText(find.byKey(const Key('model-id-field')), 'gpt-4.1');
    await tester.tap(find.byKey(const Key('model-provider-prov_fast')));
    await tester.tap(find.byKey(const Key('model-provider-prov_slow')));
    await tester.tap(find.byKey(const Key('model-save-button')));
    await tester.pumpAndSettle();

    expect(repository.load().models.single.providerIds, [
      'prov_fast',
      'prov_slow',
    ]);
  });

  testWidgets('settings screen persists runtime timeout edits', (tester) async {
    final store = _MemoryLocalKvStore();
    final repository = ProviderSettingsRepository(store: store);
    final logs = LogSignals();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsScreen(repository: repository, logs: logs),
        ),
      ),
    );

    await tester.enterText(
      find.byKey(const Key('runtime-timeout-field')),
      '90',
    );
    await tester.pump();

    expect(repository.load().runtime.requestTimeoutSeconds, 90);
  });

  testWidgets('imports pasted workflow JSON into the workbench', (
    tester,
  ) async {
    final store = _MemoryLocalKvStore();
    final repository = ProviderSettingsRepository(store: store);
    final workflowRepository = WorkflowRepository(store: store);
    final workbench = WorkbenchSignals();
    final logs = LogSignals();
    const json =
        '{"name":"Imported","data":{"canvas":{"x":0,"y":0,"zoom":1},'
        '"nodes":[{"id":"t","type":"Text","x":10,"y":20,"data":{}}],'
        '"connections":[],"version":"1.3"}}';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsScreen(
            repository: repository,
            logs: logs,
            workbench: workbench,
            workflowRepository: workflowRepository,
          ),
        ),
      ),
    );

    await tester.scrollUntilVisible(
      find.byKey(const Key('workflow-import-field')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(
      find.byKey(const Key('workflow-import-field')),
      json,
    );
    await tester.ensureVisible(find.byKey(const Key('workflow-import-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('workflow-import-button')));
    await tester.pumpAndSettle();

    expect(workbench.nodes.value.single.id, 't');
    expect(workbench.activeWorkflowName.value, 'Imported');
    expect(workflowRepository.listWorkflowIds(), contains('imported'));
    expect(
      logs.entries.value.any((e) => e.message.contains('imported')),
      isTrue,
    );
  });

  testWidgets('shows an error for invalid import JSON', (tester) async {
    final store = _MemoryLocalKvStore();
    final repository = ProviderSettingsRepository(store: store);
    final workbench = WorkbenchSignals();
    final logs = LogSignals();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsScreen(
            repository: repository,
            logs: logs,
            workbench: workbench,
            workflowRepository: WorkflowRepository(store: store),
          ),
        ),
      ),
    );

    await tester.scrollUntilVisible(
      find.byKey(const Key('workflow-import-field')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(
      find.byKey(const Key('workflow-import-field')),
      '{not valid',
    );
    await tester.ensureVisible(find.byKey(const Key('workflow-import-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('workflow-import-button')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Invalid workflow JSON'), findsOneWidget);
    expect(logs.hasErrors.value, isTrue);
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
