import 'package:signals/signals.dart';

import '../../core/models/workflow_document.dart';
import '../media/media_repository.dart';
import '../workbench/workbench_signals.dart';
import '../workbench/workbench_workflow_mapper.dart';
import 'workflow_repository.dart';

/// A saved workflow entry surfaced in the Workflows rail.
class WorkflowSummary {
  const WorkflowSummary({required this.id, required this.name});

  final String id;
  final String name;
}

/// Coordinates lightweight multi-workflow management: list, create, switch,
/// rename, delete. One workflow is active at a time (no tabs).
///
/// The active graph lives in [workbench]; this manager persists it through
/// [repository] and applies saved documents back onto the workbench.
class WorkflowManager {
  WorkflowManager({
    required this.repository,
    required this.workbench,
    this.media,
    this.flushActive,
    this.onWorkflowApplied,
  });

  final WorkflowRepository repository;
  final WorkbenchSignals workbench;
  final MediaRepository? media;

  /// Optional callback to persist the active graph before switching away
  /// (typically [WorkflowAutoSave.flush]).
  final void Function()? flushActive;

  /// Called after a workflow document is applied to the workbench. The
  /// document is passed so callers can restore transient state (e.g. image
  /// output previews from [FlowNode.data] `_lastOutput` fields).
  final void Function(WorkflowDocument document)? onWorkflowApplied;

  final workflows = signal<List<WorkflowSummary>>(const []);
  final activeWorkflowId = signal<String?>(null);

  /// Rebuilds the [workflows] list from persisted documents.
  void refresh() {
    workflows.value = [
      for (final id in repository.listWorkflowIds())
        WorkflowSummary(id: id, name: _nameFor(id)),
    ];
  }

  String _nameFor(String id) {
    final name = repository.loadWorkflow(id)?.name ?? '';
    return name.isNotEmpty ? name : id;
  }

  /// Persists the current workbench graph under [id], creating or updating it.
  void saveActive(String id, {String? name}) {
    final document = workbenchSignalsToWorkflow(workbench).copyWith(
      name: name ?? workbench.activeWorkflowName.value,
    );
    repository.saveWorkflow(id, document);
    repository.saveActiveId(id);
    if (name != null && name.isNotEmpty) {
      workbench.activeWorkflowName.value = name;
    }
    activeWorkflowId.value = id;
    refresh();
  }

  /// Saves the current graph, reusing the active id or deriving one from the
  /// workflow name (for a never-saved workflow). Returns the id used.
  String save() {
    final existing = activeWorkflowId.value;
    final id = existing ??
        _uniqueId(_slugify(workbench.activeWorkflowName.value,
            fallback: 'workflow'));
    saveActive(id);
    return id;
  }

  /// Creates an empty workflow, switching the workbench to it.
  String newWorkflow({String name = 'Untitled Workflow'}) {
    flushActive?.call();
    final id = _slugify(name, fallback: 'workflow');
    final uniqueId = _uniqueId(id);
    workbench.nodes.value = const [];
    workbench.connections.value = const [];
    workbench.clearSelection();
    workbench.activeWorkflowName.value = name;
    saveActive(uniqueId, name: name);
    return uniqueId;
  }

  /// Flushes the current graph, then loads and applies [id].
  bool switchTo(String id) {
    final document = repository.loadWorkflow(id);
    if (document == null) return false;
    flushActive?.call();
    applyWorkflowToWorkbench(workbench, document, name: document.name);
    activeWorkflowId.value = id;
    repository.saveActiveId(id);
    onWorkflowApplied?.call(document);
    return true;
  }

  /// Renames the workflow [id] (document name only; id is stable).
  void rename(String id, String name) {
    final document = repository.loadWorkflow(id);
    if (document == null) return;
    repository.saveWorkflow(id, document.copyWith(name: name));
    if (activeWorkflowId.value == id) {
      workbench.activeWorkflowName.value = name;
    }
    refresh();
  }

  /// Deletes [id] and cleans up its orphaned media.
  Future<void> delete(String id) async {
    repository.deleteWorkflow(id);
    if (activeWorkflowId.value == id) {
      activeWorkflowId.value = null;
      repository.clearActiveId();
    }
    await media?.cleanOrphanedAssets(
      repository.listWorkflowIds().toSet()..add(workbench.activeWorkflowName.value),
    );
    refresh();
  }

  String _uniqueId(String base) {
    final existing = repository.listWorkflowIds().toSet();
    if (!existing.contains(base)) return base;
    var i = 2;
    while (existing.contains('$base-$i')) {
      i += 1;
    }
    return '$base-$i';
  }
}

String _slugify(String value, {required String fallback}) {
  final slug = value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return slug.isEmpty ? fallback : slug;
}
