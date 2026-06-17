import '../../core/models/flow_node.dart';
import '../../core/models/workflow_document.dart';
import '../../core/network/provider_client.dart';
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
  WorkflowRunner({
    required this.executor,
    required this.signals,
    this.maxConcurrency = 1,
  });

  final NodeExecutor executor;
  final ExecutionSignals signals;

  /// Max nodes executed in parallel. 1 preserves the original serial behavior.
  final int maxConcurrency;

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

    if (maxConcurrency <= 1) {
      return _runSerial(plan, results);
    }
    return _runConcurrent(plan, results);
  }

  // --- Serial path (unchanged semantics) -----------------------------------

  Future<WorkflowRunResult> _runSerial(
    ExecutionPlan plan,
    Map<String, NodeExecutionResult> results,
  ) async {
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
        final result = await _executeNode(plan, node, results);
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
        signals.markNode(node.id, NodeRunState.completed, message: result.message);
      } catch (error) {
        return _failWorkflow(plan, node.id, results, error);
      }
    }

    signals.markWorkflowCompleted();
    return WorkflowRunResult(
      state: WorkflowExecutionState.completed,
      results: Map.unmodifiable(results),
    );
  }

  // --- Concurrent path -----------------------------------------------------

  Future<WorkflowRunResult> _runConcurrent(
    ExecutionPlan plan,
    Map<String, NodeExecutionResult> results,
  ) async {
    final pending = {for (final n in plan.steps) n.id};
    final remainingDeps = <String, int>{};
    for (final node in plan.steps) {
      remainingDeps[node.id] = plan.incomingConnections(node.id)
          .map((c) => c.from.nodeId)
          .toSet()
          .length;
    }
    final nodeById = {for (final n in plan.steps) n.id: n};

    while (pending.isNotEmpty) {
      if (_cancelRequested) {
        for (final id in pending) {
          signals.markNode(id, NodeRunState.skipped);
        }
        signals.markWorkflowCanceled();
        return WorkflowRunResult(
          state: WorkflowExecutionState.canceled,
          results: Map.unmodifiable(results),
        );
      }

      final ready = [
        for (final id in pending)
          if ((remainingDeps[id] ?? 0) == 0) id,
      ].take(maxConcurrency).toList();

      if (ready.isEmpty) {
        // No runnable node but work remains: dependency on a failed/absent node.
        for (final id in pending) {
          signals.markNode(id, NodeRunState.skipped);
        }
        break;
      }

      for (final id in ready) {
        signals.markNode(id, NodeRunState.running);
      }

      final batch = await Future.wait([
        for (final id in ready)
          _executeNode(plan, nodeById[id]!, results)
              .then<_NodeOutcome>((r) => _NodeOutcome.ok(id, r))
              .catchError((Object e) => _NodeOutcome.fail(id, e)),
      ]);

      for (final outcome in batch) {
        pending.remove(outcome.nodeId);
        if (outcome.error != null) {
          final message = _errorMessage(outcome.error!);
          signals.markNode(outcome.nodeId, NodeRunState.failed,
              message: message);
          for (final id in pending) {
            signals.markNode(id, NodeRunState.skipped);
          }
          signals.markWorkflowFailed(message);
          return WorkflowRunResult(
            state: WorkflowExecutionState.failed,
            results: Map.unmodifiable(results),
            error: message,
          );
        }
        results[outcome.nodeId] = outcome.result!;
        signals.markNode(outcome.nodeId, NodeRunState.completed,
            message: outcome.result!.message);
        // Decrement dependents.
        for (final c in plan.connections) {
          if (c.from.nodeId == outcome.nodeId) {
            remainingDeps[c.to.nodeId] =
                (remainingDeps[c.to.nodeId] ?? 1) - 1;
          }
        }
      }
    }

    signals.markWorkflowCompleted();
    return WorkflowRunResult(
      state: WorkflowExecutionState.completed,
      results: Map.unmodifiable(results),
    );
  }

  // --- Shared helpers ------------------------------------------------------

  Future<NodeExecutionResult> _executeNode(
    ExecutionPlan plan,
    FlowNode node,
    Map<String, NodeExecutionResult> results,
  ) {
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
    return executor.execute(node, context);
  }

  WorkflowRunResult _failWorkflow(
    ExecutionPlan plan,
    String nodeId,
    Map<String, NodeExecutionResult> results,
    Object error,
  ) {
    final message = _errorMessage(error);
    signals.markNode(nodeId, NodeRunState.failed, message: message);
    _markRemainingSkipped(plan, nodeId);
    signals.markWorkflowFailed(message);
    return WorkflowRunResult(
      state: WorkflowExecutionState.failed,
      results: Map.unmodifiable(results),
      error: message,
    );
  }

  String _errorMessage(Object error) {
    if (error is ProviderTransportException) {
      return error.error.message;
    }
    return error.toString();
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

class _NodeOutcome {
  _NodeOutcome.ok(this.nodeId, this.result) : error = null;
  _NodeOutcome.fail(this.nodeId, this.error) : result = null;

  final String nodeId;
  final NodeExecutionResult? result;
  final Object? error;
}
