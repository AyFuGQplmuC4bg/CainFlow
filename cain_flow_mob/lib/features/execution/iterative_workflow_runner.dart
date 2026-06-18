import '../../core/models/workflow_document.dart';
import '../../core/network/provider_client.dart';
import 'execution_signals.dart';
import 'node_executor.dart';

/// Result of an iterative run.
class IterativeRunResult {
  const IterativeRunResult({
    required this.state,
    required this.results,
    this.error = '',
  });

  final WorkflowExecutionState state;
  final Map<String, NodeExecutionResult> results;
  final String error;
}

/// An execution engine that supports branching and bounded loops, for graphs
/// containing control-flow nodes. Unlike the topological [WorkflowRunner], it
/// does not require a DAG: nodes may re-execute and edges may form cycles.
///
/// Model:
/// - A node becomes *ready* when at least one incoming edge on each of its
///   connected input ports carries a value from a completed upstream node.
/// - A node that produces outputs only on some ports (e.g. a condition firing
///   `true` but not `false`) leaves the other branch's edges without a value,
///   so that branch's targets don't run.
/// - [maxSteps] bounds total node executions to prevent runaway loops.
class IterativeWorkflowRunner {
  IterativeWorkflowRunner({
    required this.executor,
    required this.signals,
    this.maxSteps = 1000,
  });

  final NodeExecutor executor;
  final ExecutionSignals signals;
  final int maxSteps;

  bool _cancelRequested = false;

  void cancel() => _cancelRequested = true;

  Future<IterativeRunResult> run(WorkflowDocument workflow) async {
    _cancelRequested = false;
    final nodes = {
      for (final n in workflow.nodes)
        if (n.enabled && n.id.isNotEmpty) n.id: n,
    };
    final connections = [
      for (final c in workflow.connections)
        if (nodes.containsKey(c.from.nodeId) && nodes.containsKey(c.to.nodeId))
          c,
    ];
    signals.reset(nodes.keys);
    signals.markWorkflowRunning();

    // Live values produced per (nodeId, port).
    final portValues = <String, Map<String, dynamic>>{};
    final results = <String, NodeExecutionResult>{};

    // Seed: nodes with no incoming connections are ready immediately.
    final hasIncoming = {for (final c in connections) c.to.nodeId};
    final queue = <String>[
      for (final id in nodes.keys)
        if (!hasIncoming.contains(id)) id,
    ];

    var steps = 0;
    while (queue.isNotEmpty) {
      if (_cancelRequested) {
        signals.markWorkflowCanceled();
        return IterativeRunResult(
          state: WorkflowExecutionState.canceled,
          results: Map.unmodifiable(results),
        );
      }
      if (steps++ >= maxSteps) {
        const msg = 'Iterative run exceeded max steps (possible infinite loop)';
        signals.markWorkflowFailed(msg);
        return IterativeRunResult(
          state: WorkflowExecutionState.failed,
          results: Map.unmodifiable(results),
          error: msg,
        );
      }

      final nodeId = queue.removeAt(0);
      final node = nodes[nodeId]!;
      final incoming = [
        for (final c in connections)
          if (c.to.nodeId == nodeId) c,
      ];

      // Gather inputs from live upstream port values.
      final inputs = <String, dynamic>{};
      for (final c in incoming) {
        final value = portValues[c.from.nodeId]?[c.from.port];
        if (value != null) inputs[c.to.port] = value;
      }

      signals.markNode(nodeId, NodeRunState.running);
      try {
        final context = NodeExecutionContext(
          inputs: inputs,
          previousResults: Map.unmodifiable(results),
          isCanceled: () => _cancelRequested,
        );
        final result = await executor.execute(node, context);
        results[nodeId] = result;
        portValues[nodeId] = Map<String, dynamic>.from(result.outputs);
        signals.markNode(
          nodeId,
          NodeRunState.completed,
          message: result.message,
        );

        // Enqueue downstream nodes reachable via ports that produced a value.
        for (final c in connections) {
          if (c.from.nodeId != nodeId) continue;
          if (!result.outputs.containsKey(c.from.port)) continue;
          if (result.outputs[c.from.port] == null) continue;
          if (!queue.contains(c.to.nodeId)) queue.add(c.to.nodeId);
        }
      } on ProviderRequestCanceled {
        signals.markNode(nodeId, NodeRunState.skipped);
        signals.markWorkflowCanceled();
        return IterativeRunResult(
          state: WorkflowExecutionState.canceled,
          results: Map.unmodifiable(results),
        );
      } catch (error) {
        final msg = error.toString();
        signals.markNode(nodeId, NodeRunState.failed, message: msg);
        signals.markWorkflowFailed(msg);
        return IterativeRunResult(
          state: WorkflowExecutionState.failed,
          results: Map.unmodifiable(results),
          error: msg,
        );
      }
    }

    signals.markWorkflowCompleted();
    return IterativeRunResult(
      state: WorkflowExecutionState.completed,
      results: Map.unmodifiable(results),
    );
  }
}
