import '../../core/models/flow_connection.dart';
import '../../core/models/flow_node.dart';
import '../../core/models/workflow_document.dart';

class ExecutionPlan {
  const ExecutionPlan({required this.steps, required this.connections});

  factory ExecutionPlan.fromWorkflow(WorkflowDocument workflow) {
    final enabledNodes = [
      for (final node in workflow.nodes)
        if (node.enabled && node.id.isNotEmpty) node,
    ];
    final nodeIds = enabledNodes.map((node) => node.id).toSet();
    final validConnections = [
      for (final connection in workflow.connections)
        if (nodeIds.contains(connection.from.nodeId) &&
            nodeIds.contains(connection.to.nodeId))
          connection,
    ];
    final incomingCounts = {for (final node in enabledNodes) node.id: 0};
    final outgoing = {for (final node in enabledNodes) node.id: <String>[]};

    for (final connection in validConnections) {
      outgoing[connection.from.nodeId]!.add(connection.to.nodeId);
      incomingCounts[connection.to.nodeId] =
          (incomingCounts[connection.to.nodeId] ?? 0) + 1;
    }

    final nodesById = {for (final node in enabledNodes) node.id: node};
    final ready = [
      for (final node in enabledNodes)
        if (incomingCounts[node.id] == 0) node.id,
    ];
    final ordered = <FlowNode>[];

    while (ready.isNotEmpty) {
      final nodeId = ready.removeAt(0);
      final node = nodesById[nodeId];
      if (node == null) continue;
      ordered.add(node);

      for (final targetId in outgoing[nodeId]!) {
        final nextCount = (incomingCounts[targetId] ?? 0) - 1;
        incomingCounts[targetId] = nextCount;
        if (nextCount == 0) ready.add(targetId);
      }
    }

    if (ordered.length != enabledNodes.length) {
      throw const ExecutionPlanException(
        'Workflow contains a cycle or unresolved node dependency.',
      );
    }

    return ExecutionPlan(steps: ordered, connections: validConnections);
  }

  final List<FlowNode> steps;
  final List<FlowConnection> connections;

  FlowNode? nodeById(String nodeId) {
    for (final node in steps) {
      if (node.id == nodeId) return node;
    }
    return null;
  }

  List<FlowConnection> incomingConnections(String nodeId) {
    return [
      for (final connection in connections)
        if (connection.to.nodeId == nodeId) connection,
    ];
  }
}

class ExecutionPlanException implements Exception {
  const ExecutionPlanException(this.message);

  final String message;

  @override
  String toString() => 'ExecutionPlanException: $message';
}
