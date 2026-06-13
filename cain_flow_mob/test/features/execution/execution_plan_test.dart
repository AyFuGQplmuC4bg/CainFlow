import 'package:cain_flow_mob/core/models/flow_connection.dart';
import 'package:cain_flow_mob/core/models/flow_node.dart';
import 'package:cain_flow_mob/core/models/workflow_document.dart';
import 'package:cain_flow_mob/features/execution/execution_plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('orders enabled nodes by dependency', () {
    final plan = ExecutionPlan.fromWorkflow(
      _workflow(
        nodes: const [
          FlowNode(id: 'a', type: 'Text', x: 0, y: 0),
          FlowNode(id: 'b', type: 'TextChat', x: 0, y: 0),
          FlowNode(id: 'c', type: 'ImageGenerate', x: 0, y: 0),
          FlowNode(id: 'd', type: 'ImageSave', x: 0, y: 0),
        ],
        connections: [
          _connection('ab', 'a', 'text', 'b', 'prompt'),
          _connection('ac', 'a', 'text', 'c', 'prompt'),
          _connection('bd', 'b', 'text', 'd', 'caption'),
          _connection('cd', 'c', 'image', 'd', 'image'),
        ],
      ),
    );

    expect(plan.steps.map((node) => node.id), ['a', 'b', 'c', 'd']);
    expect(plan.incomingConnections('d'), hasLength(2));
  });

  test('ignores disabled nodes and their connections', () {
    final plan = ExecutionPlan.fromWorkflow(
      _workflow(
        nodes: const [
          FlowNode(id: 'a', type: 'Text', x: 0, y: 0),
          FlowNode(id: 'b', type: 'TextChat', x: 0, y: 0, enabled: false),
        ],
        connections: [_connection('ab', 'a', 'text', 'b', 'prompt')],
      ),
    );

    expect(plan.steps.map((node) => node.id), ['a']);
    expect(plan.connections, isEmpty);
  });

  test('rejects cyclic workflows', () {
    expect(
      () => ExecutionPlan.fromWorkflow(
        _workflow(
          nodes: const [
            FlowNode(id: 'a', type: 'Text', x: 0, y: 0),
            FlowNode(id: 'b', type: 'TextChat', x: 0, y: 0),
          ],
          connections: [
            _connection('ab', 'a', 'text', 'b', 'prompt'),
            _connection('ba', 'b', 'text', 'a', 'prompt'),
          ],
        ),
      ),
      throwsA(isA<ExecutionPlanException>()),
    );
  });
}

WorkflowDocument _workflow({
  required List<FlowNode> nodes,
  required List<FlowConnection> connections,
}) {
  return WorkflowDocument(
    canvas: WorkflowCanvas.empty(),
    nodes: nodes,
    connections: connections,
    version: WorkflowDocument.defaultVersion,
  );
}

FlowConnection _connection(
  String id,
  String fromNodeId,
  String fromPort,
  String toNodeId,
  String toPort,
) {
  return FlowConnection(
    id: id,
    from: FlowEndpoint(nodeId: fromNodeId, port: fromPort),
    to: FlowEndpoint(nodeId: toNodeId, port: toPort),
  );
}
