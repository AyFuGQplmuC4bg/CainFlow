import '../../core/models/flow_connection.dart';
import '../../core/models/flow_node.dart';
import '../../core/models/workflow_document.dart';
import 'workbench_signals.dart';

/// Maps the in-memory workbench graph (signals) into a [WorkflowDocument]
/// the [WorkflowRunner] can execute.
WorkflowDocument workbenchToWorkflow({
  required List<WorkbenchNode> nodes,
  required List<WorkbenchConnection> connections,
  NodeOffset panOffset = const NodeOffset(0, 0),
  double zoom = 1,
}) {
  return WorkflowDocument(
    canvas: WorkflowCanvas(x: panOffset.dx, y: panOffset.dy, zoom: zoom),
    nodes: [for (final node in nodes) _nodeToFlowNode(node)],
    connections: [
      for (final connection in connections) _connectionToFlowConnection(connection),
    ],
    version: WorkflowDocument.defaultVersion,
  );
}

/// Convenience wrapper reading directly from a [WorkbenchSignals] instance.
WorkflowDocument workbenchSignalsToWorkflow(WorkbenchSignals signals) {
  return workbenchToWorkflow(
    nodes: signals.nodes.value,
    connections: signals.connections.value,
    panOffset: signals.panOffset.value,
    zoom: signals.zoom.value,
  );
}

FlowNode _nodeToFlowNode(WorkbenchNode node) {
  return FlowNode(
    id: node.id,
    type: node.type,
    x: node.x,
    y: node.y,
    customTitle: node.title.isNotEmpty && node.title != node.type
        ? node.title
        : null,
  );
}

FlowConnection _connectionToFlowConnection(WorkbenchConnection connection) {
  return FlowConnection(
    id: connection.id,
    from: FlowEndpoint(
      nodeId: connection.fromNodeId,
      port: connection.fromPort,
      type: connection.type,
    ),
    to: FlowEndpoint(
      nodeId: connection.toNodeId,
      port: connection.toPort,
      type: connection.type,
    ),
    type: connection.type,
  );
}

/// Applies a [WorkflowDocument] onto [signals], replacing the current graph.
void applyWorkflowToWorkbench(
  WorkbenchSignals signals,
  WorkflowDocument document, {
  String? name,
}) {
  signals.nodes.value = [
    for (final node in document.nodes)
      WorkbenchNode(
        id: node.id,
        type: node.type,
        title: node.title,
        x: node.x,
        y: node.y,
      ),
  ];
  signals.connections.value = [
    for (final connection in document.connections)
      WorkbenchConnection(
        id: connection.id,
        fromNodeId: connection.from.nodeId,
        fromPort: connection.from.port,
        toNodeId: connection.to.nodeId,
        toPort: connection.to.port,
        type: connection.type.isNotEmpty ? connection.type : connection.from.type,
      ),
  ];
  signals.clearSelection();
  if (name != null && name.isNotEmpty) {
    signals.activeWorkflowName.value = name;
  }
}
