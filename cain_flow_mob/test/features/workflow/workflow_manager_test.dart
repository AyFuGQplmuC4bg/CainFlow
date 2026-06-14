import 'package:cain_flow_mob/core/storage/local_kv_store.dart';
import 'package:cain_flow_mob/features/workbench/workbench_signals.dart';
import 'package:cain_flow_mob/features/workflow/workflow_manager.dart';
import 'package:cain_flow_mob/features/workflow/workflow_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _MemoryStore store;
  late WorkflowRepository repository;
  late WorkbenchSignals workbench;
  late WorkflowManager manager;
  late int flushes;

  setUp(() {
    store = _MemoryStore();
    repository = WorkflowRepository(store: store);
    workbench = WorkbenchSignals();
    flushes = 0;
    manager = WorkflowManager(
      repository: repository,
      workbench: workbench,
      flushActive: () => flushes += 1,
    );
  });

  test('newWorkflow creates an empty graph and registers it', () {
    final id = manager.newWorkflow(name: 'My Flow');
    expect(id, 'my-flow');
    expect(workbench.nodes.value, isEmpty);
    expect(workbench.activeWorkflowName.value, 'My Flow');
    expect(repository.listWorkflowIds(), contains('my-flow'));
    expect(manager.activeWorkflowId.value, 'my-flow');
  });

  test('newWorkflow disambiguates duplicate slugs', () {
    manager.newWorkflow(name: 'Flow');
    final second = manager.newWorkflow(name: 'Flow');
    expect(second, 'flow-2');
  });

  test('switchTo flushes the active graph then applies the target', () {
    // Seed a saved workflow with one node.
    workbench.updateNodeData('node_text_prompt', {'text': 'hi'});
    manager.saveActive('first', name: 'First');

    final beforeFlushes = flushes;
    manager.newWorkflow(name: 'Second');
    expect(flushes, greaterThan(beforeFlushes));

    expect(manager.switchTo('first'), isTrue);
    expect(workbench.activeWorkflowName.value, 'First');
    expect(
      workbench.nodes.value.any((n) => n.id == 'node_text_prompt'),
      isTrue,
    );
  });

  test('rename updates the document name and active label', () {
    manager.saveActive('wf', name: 'Old');
    manager.activeWorkflowId.value = 'wf';
    manager.rename('wf', 'New');
    expect(repository.loadWorkflow('wf')?.name, 'New');
    expect(workbench.activeWorkflowName.value, 'New');
  });

  test('delete removes the workflow from the index', () async {
    manager.saveActive('wf', name: 'Doomed');
    expect(repository.listWorkflowIds(), contains('wf'));
    await manager.delete('wf');
    expect(repository.listWorkflowIds(), isNot(contains('wf')));
  });

  test('refresh lists summaries with document names', () {
    manager.saveActive('a', name: 'Alpha');
    manager.saveActive('b', name: 'Beta');
    manager.refresh();
    final names = manager.workflows.value.map((w) => w.name).toList();
    expect(names, containsAll(['Alpha', 'Beta']));
  });
}

class _MemoryStore implements LocalKvStore {
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
