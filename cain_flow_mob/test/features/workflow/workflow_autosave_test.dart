import 'dart:convert';

import 'package:cain_flow_mob/core/storage/local_kv_store.dart';
import 'package:cain_flow_mob/core/storage/storage_keys.dart';
import 'package:cain_flow_mob/features/workbench/workbench_signals.dart';
import 'package:cain_flow_mob/features/workflow/workflow_autosave.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('workbench session round trips through JSON', () {
    final state = WorkbenchSignals();
    state.selectNode('node_image_generate');
    state.moveCanvas(const NodeOffset(12, 8));
    state.setZoom(1.25);

    final restored = WorkbenchSignals();
    restored.restoreSession(state.toSessionJson());

    expect(restored.selectedNodeId.value, 'node_image_generate');
    expect(restored.panOffset.value.dx, 12);
    expect(restored.panOffset.value.dy, 8);
    expect(restored.zoom.value, 1.25);
    expect(restored.nodes.value.length, state.nodes.value.length);
    expect(restored.connections.value.length, state.connections.value.length);
  });

  test('autosave persists session snapshots after debounce', () async {
    final store = _MemoryLocalKvStore();
    final state = WorkbenchSignals();
    final autosave = WorkflowAutosave(
      store: store,
      workbench: state,
      workflowId: 'demo',
      debounceDuration: const Duration(milliseconds: 1),
    );

    autosave.start();
    state.moveNode('node_image_generate', const NodeOffset(5, 0));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    autosave.dispose();

    final raw = store.getString(StorageKeys.workflowSession('demo'));
    expect(raw, isNotNull);
    final decoded = jsonDecode(raw!) as Map<String, dynamic>;
    expect(decoded['nodes'], isA<List>());
    expect(decoded['selectedNodeId'], isNull);
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
