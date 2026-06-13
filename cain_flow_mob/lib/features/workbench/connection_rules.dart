import '../../core/models/flow_connection.dart';
import '../../core/models/flow_node.dart';
import '../../core/models/workflow_document.dart';
import '../execution/execution_plan.dart';
import 'workbench_signals.dart';

/// Outcome of validating a proposed connection between two ports.
enum ConnectionRejection {
  none,
  selfConnection,
  typeMismatch,
  cycle,
}

class ConnectionAttempt {
  const ConnectionAttempt({
    required this.fromNodeId,
    required this.fromPort,
    required this.fromType,
    required this.toNodeId,
    required this.toPort,
    required this.toType,
  });

  final String fromNodeId;
  final String fromPort;
  final String fromType;
  final String toNodeId;
  final String toPort;
  final String toType;
}

/// Pure validation for a point-select connection. UI calls this before
/// committing a [WorkbenchConnection]. Single-input replacement is handled
/// by the signals layer (a new edge replaces an existing one on the same
/// input port), so it is not treated as a rejection here.
ConnectionRejection validateConnection(
  ConnectionAttempt attempt,
  List<WorkbenchNode> nodes,
  List<WorkbenchConnection> existing,
) {
  if (attempt.fromNodeId == attempt.toNodeId) {
    return ConnectionRejection.selfConnection;
  }
  if (attempt.fromType.isNotEmpty &&
      attempt.toType.isNotEmpty &&
      attempt.fromType != attempt.toType) {
    return ConnectionRejection.typeMismatch;
  }
  if (_wouldCycle(attempt, nodes, existing)) {
    return ConnectionRejection.cycle;
  }
  return ConnectionRejection.none;
}

bool _wouldCycle(
  ConnectionAttempt attempt,
  List<WorkbenchNode> nodes,
  List<WorkbenchConnection> existing,
) {
  // Build a candidate graph: existing edges minus any replaced same-input
  // edge, plus the proposed edge, then reuse the execution plan's cycle check.
  final kept = [
    for (final c in existing)
      if (!(c.toNodeId == attempt.toNodeId && c.toPort == attempt.toPort)) c,
  ];

  final flowNodes = [
    for (final n in nodes) FlowNode(id: n.id, type: n.type, x: n.x, y: n.y),
  ];
  final flowConnections = [
    for (final c in kept)
      FlowConnection(
        id: c.id,
        from: FlowEndpoint(nodeId: c.fromNodeId, port: c.fromPort, type: c.type),
        to: FlowEndpoint(nodeId: c.toNodeId, port: c.toPort, type: c.type),
        type: c.type,
      ),
    FlowConnection(
      id: '__candidate__',
      from: FlowEndpoint(
        nodeId: attempt.fromNodeId,
        port: attempt.fromPort,
        type: attempt.fromType,
      ),
      to: FlowEndpoint(
        nodeId: attempt.toNodeId,
        port: attempt.toPort,
        type: attempt.toType,
      ),
      type: attempt.fromType,
    ),
  ];

  final document = WorkflowDocument(
    canvas: const WorkflowCanvas(x: 0, y: 0, zoom: 1),
    nodes: flowNodes,
    connections: flowConnections,
    version: WorkflowDocument.defaultVersion,
  );

  try {
    ExecutionPlan.fromWorkflow(document);
    return false;
  } on ExecutionPlanException {
    return true;
  }
}
