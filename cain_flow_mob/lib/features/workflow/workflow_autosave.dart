import 'dart:async';
import 'dart:convert';

import 'package:signals/signals.dart';

import '../../core/storage/local_kv_store.dart';
import '../../core/storage/storage_keys.dart';
import '../workbench/workbench_signals.dart';

class WorkflowAutosave {
  WorkflowAutosave({
    required this.store,
    required this.workbench,
    required this.workflowId,
    this.debounceDuration = const Duration(milliseconds: 300),
  });

  static const currentSchemaVersion = 1;

  final LocalKvStore store;
  final WorkbenchSignals workbench;
  final String workflowId;
  final Duration debounceDuration;

  EffectCleanup? _disposeEffect;
  Timer? _timer;

  void start() {
    if (_disposeEffect != null) return;
    store.setInt(StorageKeys.schemaVersion, currentSchemaVersion);
    _disposeEffect = effect(() {
      workbench.activeWorkflowName.value;
      workbench.nodes.value;
      workbench.connections.value;
      workbench.selectedNodeId.value;
      workbench.panOffset.value;
      workbench.zoom.value;
      _scheduleSave();
    });
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _disposeEffect?.call();
    _disposeEffect = null;
  }

  void flush() {
    _timer?.cancel();
    _timer = null;
    _saveNow();
  }

  void _scheduleSave() {
    _timer?.cancel();
    _timer = Timer(debounceDuration, _saveNow);
  }

  void _saveNow() {
    store.setString(
      StorageKeys.workflowSession(workflowId),
      jsonEncode(workbench.toSessionJson()),
    );
  }
}
