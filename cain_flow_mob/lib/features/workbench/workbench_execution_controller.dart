import '../../core/models/workflow_document.dart';
import '../background/background_execution_coordinator.dart';
import '../execution/execution_signals.dart';
import '../execution/iterative_workflow_runner.dart';
import '../execution/node_executor.dart';
import '../execution/workflow_runner.dart';
import '../history/history_repository.dart';
import '../logs/log_signals.dart';
import 'completion_feedback.dart';
import 'workbench_signals.dart';
import 'workbench_workflow_mapper.dart';

/// Bridges the workbench UI Run/Stop actions to the real [WorkflowRunner].
///
/// Owns execution state so the workbench signals only track UI run state.
class WorkbenchExecutionController {
  WorkbenchExecutionController({
    required this.workbench,
    required this.executor,
    ExecutionSignals? executionSignals,
    LogSignals? logs,
    this.maxConcurrency = 1,
    this.historyRepository,
    CompletionFeedback? feedback,
    BackgroundExecutionCoordinator? backgroundCoordinator,
  }) : executionSignals = executionSignals ?? ExecutionSignals(),
       logs = logs ?? logSignals,
       feedback = feedback ?? CompletionFeedback(),
       backgroundCoordinator =
           backgroundCoordinator ?? defaultBackgroundExecutionCoordinator;

  final WorkbenchSignals workbench;
  final NodeExecutor executor;
  final BackgroundExecutionCoordinator? backgroundCoordinator;
  final ExecutionSignals executionSignals;
  final LogSignals logs;

  /// Resolved per-run from settings by the screen; 1 keeps serial execution.
  final int maxConcurrency;

  /// Optional history sink; when set, a completed run appends an entry.
  final HistoryRepository? historyRepository;

  /// Plays haptic/sound cues when a run finishes.
  final CompletionFeedback feedback;

  void Function()? _cancelActive;
  bool _isRunning = false;
  String? _activeJobId;

  bool get isRunning => _isRunning;

  Future<WorkflowRunResult?> run({
    WorkflowDocument? workflow,
    String? jobId,
  }) async {
    if (_isRunning) return null;
    _isRunning = true;
    workbench.runState.value = WorkbenchRunState.running;

    final workflowDocument = workflow ?? workbenchSignalsToWorkflow(workbench);
    final requestedJobId = jobId;
    final backgroundJob = requestedJobId == null
        ? backgroundCoordinator?.enqueueWorkflow(workflow: workflowDocument)
        : backgroundCoordinator?.loadJob(requestedJobId) ??
              backgroundCoordinator?.enqueueWorkflow(
                workflow: workflowDocument,
                jobId: requestedJobId,
              );
    final hasControlFlow = workbench.nodes.value.any(
      (n) => n.type.startsWith('Control'),
    );
    final coordinator = backgroundCoordinator;
    final resolvedJobId = backgroundJob?.jobId;
    _activeJobId = resolvedJobId;
    executionSignals.backgroundJobId.value = resolvedJobId ?? '';

    logs.add(
      LogLevel.info,
      'Workflow run started: ${workbench.activeWorkflowName.value}',
      scope: 'workbench',
    );

    try {
      if (resolvedJobId != null) {
        coordinator?.markRunning(resolvedJobId);
      }
      final WorkflowRunResult result;
      if (hasControlFlow) {
        final runner = IterativeWorkflowRunner(
          executor: executor,
          signals: executionSignals,
        );
        _cancelActive = runner.cancel;
        final iterative = await runner.run(workflowDocument);
        result = WorkflowRunResult(
          state: iterative.state,
          results: iterative.results,
          error: iterative.error,
        );
      } else {
        final runner = WorkflowRunner(
          executor: executor,
          signals: executionSignals,
          maxConcurrency: maxConcurrency,
        );
        _cancelActive = runner.cancel;
        result = await runner.run(workflowDocument);
      }
      _recordImageOutputs(result);
      _recordHistory(result);
      if (resolvedJobId != null) {
        switch (result.state) {
          case WorkflowExecutionState.completed:
            coordinator?.markCompleted(resolvedJobId);
          case WorkflowExecutionState.failed:
            coordinator?.markFailed(resolvedJobId, error: result.error);
          case WorkflowExecutionState.canceled:
            coordinator?.markCanceled(resolvedJobId);
          case WorkflowExecutionState.idle:
          case WorkflowExecutionState.running:
            break;
        }
      }
      _onResult(result);
      return result;
    } catch (error) {
      if (resolvedJobId != null) {
        coordinator?.markFailed(resolvedJobId, error: error.toString());
      }
      logs.add(
        LogLevel.error,
        'Workflow run crashed: $error',
        scope: 'workbench',
      );
      rethrow;
    } finally {
      _isRunning = false;
      _cancelActive = null;
      _activeJobId = null;
      executionSignals.backgroundJobId.value = '';
      if (workbench.runState.value == WorkbenchRunState.running) {
        workbench.runState.value = WorkbenchRunState.idle;
      }
    }
  }

  String? queueBackgroundRun(WorkflowDocument workflow, {String? jobId}) {
    final snapshot = backgroundCoordinator?.enqueueWorkflow(
      workflow: workflow,
      jobId: jobId,
    );
    if (snapshot == null) return null;
    executionSignals.backgroundJobId.value = snapshot.jobId;
    workbench.runState.value = WorkbenchRunState.running;
    return snapshot.jobId;
  }

  void stop() {
    final jobId = _activeJobId ?? executionSignals.backgroundJobId.value.trim();
    if (_isRunning) {
      _cancelActive?.call();
    }
    if (jobId.isNotEmpty) {
      backgroundCoordinator?.markCanceled(jobId);
    }
    workbench.runState.value = WorkbenchRunState.stopped;
    logs.add(LogLevel.info, 'Workflow run stop requested', scope: 'workbench');
  }

  /// Captures image outputs (`{kind: url|asset}`) so the canvas can show
  /// thumbnails on ImageGenerate/ImagePreview/ImageImport nodes after a run.
  ///
  /// Also writes `_lastOutput` into each producing node's data map so the
  /// payload survives workflow serialisation and can be restored on next load.
  /// Nodes from earlier runs that are not in this run's outputs still retain
  /// their previous `_lastOutput`, so old previews are not lost for nodes that
  /// were not part of this execution.
  void _recordImageOutputs(WorkflowRunResult result) {
    // Collect this run's new image outputs.
    final newOutputs = <String, Map<String, dynamic>>{};
    result.results.forEach((nodeId, nodeResult) {
      final image = nodeResult.outputs['image'];
      if (image is Map) {
        newOutputs[nodeId] = Map<String, dynamic>.from(image);
      }
    });

    // Seed imageOutputs with any persisted _lastOutput from node data so that
    // nodes not involved in this run still show their previous result.
    for (final node in workbench.nodes.value) {
      final last = node.data['_lastOutput'];
      if (last is Map && !newOutputs.containsKey(node.id)) {
        executionSignals.setImageOutput(
          node.id,
          Map<String, dynamic>.from(last),
        );
      }
    }

    // Apply and publish new outputs.
    newOutputs.forEach((nodeId, payload) {
      executionSignals.setImageOutput(nodeId, payload);
    });

    // Persist new outputs into node data (bypasses mutation tracking so this
    // doesn't create an undo snapshot; the auto-save will pick it up).
    if (newOutputs.isNotEmpty) {
      workbench.nodes.value = [
        for (final node in workbench.nodes.value)
          if (newOutputs.containsKey(node.id))
            node.withData({...node.data, '_lastOutput': newOutputs[node.id]})
          else
            node,
      ];
    }
  }

  /// Appends a history entry for a completed run, capturing the last image
  /// and text outputs as reviewable content pointers.
  void _recordHistory(WorkflowRunResult result) {
    final repo = historyRepository;
    if (repo == null || result.state != WorkflowExecutionState.completed) {
      return;
    }
    final nodesById = {for (final node in workbench.nodes.value) node.id: node};
    final outputs = <RunOutput>[];

    result.results.forEach((nodeId, nodeResult) {
      final node = nodesById[nodeId];
      final nodeTitle = node?.title ?? '';
      nodeResult.outputs.forEach((key, value) {
        final outputId = '${nodeId}_$key_${outputs.length}';
        if (key == 'image' && value is Map) {
          outputs.addAll(
            _imageOutputsFromPayload(
              outputId: outputId,
              nodeId: nodeId,
              nodeTitle: nodeTitle,
              payload: Map<String, dynamic>.from(value),
            ),
          );
          return;
        }
        if (_isTextOutputKey(key) && value != null) {
          final text = value.toString().trim();
          if (text.isNotEmpty) {
            outputs.add(
              RunOutput(
                id: outputId,
                kind: RunOutputKind.text,
                nodeId: nodeId,
                nodeTitle: nodeTitle,
                text: text,
              ),
            );
          }
        }
      });
    });

    if (outputs.isEmpty) return;

    final thumbnail = outputs
        .where((output) => output.kind == RunOutputKind.image)
        .map((output) => output.thumbnailRelativePath)
        .firstWhere((path) => path.isNotEmpty, orElse: () => '');
    final startedAt = executionSignals.workflowStartedAt.value;
    final finishedAt = DateTime.now().toUtc();
    final duration = startedAt == null
        ? 0
        : finishedAt.difference(startedAt.toUtc()).inMilliseconds;

    final textPrompt = outputs
        .where((output) => output.kind == RunOutputKind.text)
        .map((output) => output.text)
        .firstWhere((text) => text.isNotEmpty, orElse: () => '');

    final keyNodeTitles = [
      for (final node in workbench.nodes.value)
        if (result.results.containsKey(node.id) && node.title.trim().isNotEmpty)
          node.title.trim(),
    ].take(4).toList();

    final stageKind = workbench.nodes.value
        .map((node) => node.type)
        .firstWhere((type) => type.isNotEmpty, orElse: () => 'workflow');
    final stageLabel = keyNodeTitles.isEmpty
        ? workbench.activeWorkflowName.value
        : keyNodeTitles.join(' -> ');

    final firstImage = outputs
        .where((output) => output.kind == RunOutputKind.image)
        .cast<RunOutput?>()
        .firstWhere((output) => output != null, orElse: () => null);

    repo.add(
      HistoryEntry(
        id: 'h_${DateTime.now().microsecondsSinceEpoch}',
        workflowName: workbench.activeWorkflowName.value,
        createdAt: finishedAt,
        durationMillis: duration < 0 ? 0 : duration,
        stage: StageSummary(
          label: stageLabel,
          kind: stageKind,
          nodeCount: workbench.nodes.value.length,
          keyNodeTitles: keyNodeTitles,
        ),
        prompt: textPrompt,
        thumbnailRelativePath: thumbnail,
        resultRelativePath: firstImage?.relativePath ?? '',
        resultUrl: firstImage?.url ?? '',
        outputs: outputs,
      ),
    );
  }

  List<RunOutput> _imageOutputsFromPayload({
    required String outputId,
    required String nodeId,
    required String nodeTitle,
    required Map<String, dynamic> payload,
  }) {
    if (payload['kind']?.toString() == 'images') {
      final items = payload['items'];
      if (items is! List) return const [];
      return [
        for (var i = 0; i < items.length; i++)
          if (items[i] is Map)
            ..._imageOutputsFromPayload(
              outputId: '${outputId}_$i',
              nodeId: nodeId,
              nodeTitle: nodeTitle,
              payload: Map<String, dynamic>.from(items[i] as Map),
            ),
      ];
    }
    final relativePath = payload['relativePath']?.toString() ?? '';
    final thumbnailRelativePath =
        payload['thumbnailRelativePath']?.toString() ?? '';
    final url = payload['url']?.toString() ?? '';
    if (relativePath.isEmpty && thumbnailRelativePath.isEmpty && url.isEmpty) {
      return const [];
    }
    return [
      RunOutput(
        id: outputId,
        kind: RunOutputKind.image,
        nodeId: nodeId,
        nodeTitle: nodeTitle,
        relativePath: relativePath,
        thumbnailRelativePath: thumbnailRelativePath,
        url: url,
        mimeType: payload['mimeType']?.toString() ?? '',
      ),
    ];
  }

  bool _isTextOutputKey(String key) {
    return key == 'text' || key == 'content' || key == 'result';
  }

  void _onResult(WorkflowRunResult result) {
    switch (result.state) {
      case WorkflowExecutionState.completed:
        workbench.runState.value = WorkbenchRunState.idle;
        logs.add(LogLevel.info, 'Workflow run completed', scope: 'workbench');
        feedback.success();
      case WorkflowExecutionState.failed:
        workbench.runState.value = WorkbenchRunState.idle;
        logs.add(
          LogLevel.error,
          'Workflow run failed: ${result.error}',
          scope: 'workbench',
        );
        feedback.failure();
      case WorkflowExecutionState.canceled:
        workbench.runState.value = WorkbenchRunState.stopped;
        logs.add(LogLevel.warning, 'Workflow run canceled', scope: 'workbench');
      case WorkflowExecutionState.idle:
      case WorkflowExecutionState.running:
        workbench.runState.value = WorkbenchRunState.idle;
    }
  }
}
