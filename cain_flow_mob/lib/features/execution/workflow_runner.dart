import '../../core/models/workflow_document.dart';
import 'execution_plan.dart';
import 'execution_signals.dart';
import 'node_executor.dart';

class WorkflowRunResult {
  const WorkflowRunResult({
    required this.state,
    required this.results,
    this.error = '',
  });

  final WorkflowExecutionState state;
  final Map<String, NodeExecutionResult> results;
  final String error;
}

class WorkflowRunner {
  WorkflowRunner({required this.executor, required this.signals});

  final NodeExecutor executor;
  final ExecutionSignals signals;

  bool _cancelRequested = false;

  void cancel() {
    _cancelRequested = true;
  }

  Future<WorkflowRunResult> run(WorkflowDocument workflow) async {
    final plan = ExecutionPlan.fromWorkflow(workflow);
    final results = <String, NodeExecutionResult>{};
    _cancelRequested = false;
    signals.reset(plan.steps.map((node) => node.id));
    signals.markWorkflowRunning();

    for (final node in plan.steps) {
      if (_cancelRequested) {
        _markRemainingSkipped(plan, node.id);
        signals.markWorkflowCanceled();
        return WorkflowRunResult(
          state: WorkflowExecutionState.canceled,
          results: Map.unmodifiable(results),
        );
      }

      signals.markNode(node.id, NodeRunState.running);
      try {
        final incoming = plan.incomingConnections(node.id);
        final context = NodeExecutionContext(
          inputs: collectNodeInputs(
            node: node,
            incomingConnections: incoming,
            previousResults: results,
          ),
          previousResults: Map.unmodifiable(results),
          isCanceled: () => _cancelRequested,
        );
        final result = await executor.execute(node, context);
        if (_cancelRequested) {
          signals.markNode(node.id, NodeRunState.skipped);
          _markRemainingSkipped(plan, node.id);
          signals.markWorkflowCanceled();
          return WorkflowRunResult(
            state: WorkflowExecutionState.canceled,
            results: Map.unmodifiable(results),
          );
        }
        results[node.id] = result;
        signals.markNode(
          node.id,
          NodeRunState.completed,
          message: result.message,
        );
      } catch (error) {
        final message = error.toString();
        signals.markNode(node.id, NodeRunState.failed, message: message);
        _markRemainingSkipped(plan, node.id);
        signals.markWorkflowFailed(message);
        return WorkflowRunResult(
          state: WorkflowExecutionState.failed,
          results: Map.unmodifiable(results),
          error: message,
        );
      }
    }

    signals.markWorkflowCompleted();
    return WorkflowRunResult(
      state: WorkflowExecutionState.completed,
      results: Map.unmodifiable(results),
    );
  }

  void _markRemainingSkipped(ExecutionPlan plan, String afterNodeId) {
    var shouldSkip = false;
    for (final node in plan.steps) {
      if (shouldSkip &&
          signals.nodeStates.value[node.id]?.state == NodeRunState.pending) {
        signals.markNode(node.id, NodeRunState.skipped);
      }
      if (node.id == afterNodeId) shouldSkip = true;
    }
  }
}
