import 'dart:async';

import 'package:signals/signals.dart';

import '../workflow/workflow_manager.dart';
import 'workbench_signals.dart';

/// Watches the workbench graph signals and automatically persists changes to
/// the active workflow. Auto-save only fires when [WorkflowManager.activeWorkflowId]
/// is non-null — i.e. the workflow has been explicitly saved at least once and
/// has a stable ID. Unsaved ("Untitled") graphs still require a manual first Save.
///
/// Pan and zoom are also watched so the canvas position is remembered.
class WorkflowAutoSave {
  WorkflowAutoSave({
    required this.workbench,
    required this.manager,
    this.debounce = const Duration(milliseconds: 600),
  }) {
    _unsubscribe = effect(_watch);
  }

  final WorkbenchSignals workbench;
  final WorkflowManager manager;
  final Duration debounce;

  void Function()? _unsubscribe;
  Timer? _timer;
  bool _dirty = false;

  void _watch() {
    // Register dependencies on all graph signals.
    workbench.nodes.value;
    workbench.connections.value;
    workbench.panOffset.value;
    workbench.zoom.value;
    workbench.activeWorkflowName.value;

    _dirty = true;
    _timer?.cancel();
    _timer = Timer(debounce, _persist);
  }

  void _persist() {
    if (!_dirty) return;
    final id = manager.activeWorkflowId.value;
    if (id == null) return; // Unsaved workflow — wait for manual Save.
    manager.saveActive(id);
    _dirty = false;
  }

  /// Flush any pending debounced save immediately (e.g. before switching
  /// workflows or closing the app).
  void flush() {
    if (!_dirty) return;
    _timer?.cancel();
    _persist();
  }

  void dispose() {
    _timer?.cancel();
    _unsubscribe?.call();
  }
}
