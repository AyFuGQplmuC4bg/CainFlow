import 'package:signals/signals.dart';

import 'workbench_signals.dart';

/// A captured graph state for undo/redo.
class WorkbenchSnapshot {
  const WorkbenchSnapshot({required this.nodes, required this.connections});

  final List<WorkbenchNode> nodes;
  final List<WorkbenchConnection> connections;
}

/// Bounded undo/redo stack over the workbench graph (nodes + connections).
///
/// The caller records a snapshot *before* a mutation; [undo]/[redo] restore
/// graph state without disturbing pan/zoom/selection.
class WorkbenchHistory {
  WorkbenchHistory({required this.workbench, this.limit = 50});

  final WorkbenchSignals workbench;
  final int limit;

  final _undo = <WorkbenchSnapshot>[];
  final _redo = <WorkbenchSnapshot>[];

  final canUndo = signal(false);
  final canRedo = signal(false);

  bool _restoring = false;

  /// Captures the current graph onto the undo stack and clears redo.
  /// No-op while a restore is in progress (so undo/redo don't self-record).
  void record() {
    if (_restoring) return;
    _undo.add(_snapshot());
    if (_undo.length > limit) _undo.removeAt(0);
    _redo.clear();
    _sync();
  }

  void undo() {
    if (_undo.isEmpty) return;
    final current = _snapshot();
    final previous = _undo.removeLast();
    _redo.add(current);
    _apply(previous);
    _sync();
  }

  void redo() {
    if (_redo.isEmpty) return;
    final current = _snapshot();
    final next = _redo.removeLast();
    _undo.add(current);
    _apply(next);
    _sync();
  }

  void clear() {
    _undo.clear();
    _redo.clear();
    _sync();
  }

  WorkbenchSnapshot _snapshot() {
    return WorkbenchSnapshot(
      nodes: List.of(workbench.nodes.value),
      connections: List.of(workbench.connections.value),
    );
  }

  void _apply(WorkbenchSnapshot snapshot) {
    _restoring = true;
    workbench.nodes.value = List.of(snapshot.nodes);
    workbench.connections.value = List.of(snapshot.connections);
    // Drop selection if it points at a node that no longer exists.
    final ids = snapshot.nodes.map((n) => n.id).toSet();
    if (!ids.contains(workbench.selectedNodeId.value)) {
      workbench.selectedNodeId.value = null;
    }
    _restoring = false;
  }

  void _sync() {
    canUndo.value = _undo.isNotEmpty;
    canRedo.value = _redo.isNotEmpty;
  }
}
