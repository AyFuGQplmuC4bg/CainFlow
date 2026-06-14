import '../execution/execution_signals.dart';
import '../execution/node_executor.dart';
import '../execution/workflow_runner.dart';
import '../logs/log_signals.dart';
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
  }) : executionSignals = executionSignals ?? ExecutionSignals(),
       logs = logs ?? logSignals;

  final WorkbenchSignals workbench;
  final NodeExecutor executor;
  final ExecutionSignals executionSignals;
  final LogSignals logs;

  /// Resolved per-run from settings by the screen; 1 keeps serial execution.
  final int maxConcurrency;

  WorkflowRunner? _runner;
  bool _isRunning = false;

  bool get isRunning => _isRunning;

  Future<WorkflowRunResult?> run() async {
    if (_isRunning) return null;
    _isRunning = true;
    workbench.runState.value = WorkbenchRunState.running;

    final workflow = workbenchSignalsToWorkflow(workbench);
    final runner = WorkflowRunner(
      executor: executor,
      signals: executionSignals,
      maxConcurrency: maxConcurrency,
    );
    _runner = runner;

    logs.add(
      LogLevel.info,
      'Workflow run started: ${workbench.activeWorkflowName.value}',
      scope: 'workbench',
    );

    try {
      final result = await runner.run(workflow);
      _recordImageOutputs(result);
      _onResult(result);
      return result;
    } catch (error) {
      logs.add(
        LogLevel.error,
        'Workflow run crashed: $error',
        scope: 'workbench',
      );
      rethrow;
    } finally {
      _isRunning = false;
      _runner = null;
      if (workbench.runState.value == WorkbenchRunState.running) {
        workbench.runState.value = WorkbenchRunState.idle;
      }
    }
  }

  void stop() {
    if (!_isRunning) return;
    _runner?.cancel();
    workbench.runState.value = WorkbenchRunState.stopped;
    logs.add(LogLevel.info, 'Workflow run stop requested', scope: 'workbench');
  }

  /// Captures image outputs (`{kind: url|asset}`) so the canvas can show
  /// thumbnails on ImageGenerate/ImagePreview/ImageImport nodes after a run.
  void _recordImageOutputs(WorkflowRunResult result) {
    result.results.forEach((nodeId, nodeResult) {
      final image = nodeResult.outputs['image'];
      if (image is Map) {
        executionSignals.setImageOutput(
          nodeId,
          Map<String, dynamic>.from(image),
        );
      }
    });
  }

  void _onResult(WorkflowRunResult result) {    switch (result.state) {
      case WorkflowExecutionState.completed:
        workbench.runState.value = WorkbenchRunState.idle;
        logs.add(LogLevel.info, 'Workflow run completed', scope: 'workbench');
      case WorkflowExecutionState.failed:
        workbench.runState.value = WorkbenchRunState.idle;
        logs.add(
          LogLevel.error,
          'Workflow run failed: ${result.error}',
          scope: 'workbench',
        );
      case WorkflowExecutionState.canceled:
        workbench.runState.value = WorkbenchRunState.stopped;
        logs.add(LogLevel.warning, 'Workflow run canceled', scope: 'workbench');
      case WorkflowExecutionState.idle:
      case WorkflowExecutionState.running:
        workbench.runState.value = WorkbenchRunState.idle;
    }
  }
}
