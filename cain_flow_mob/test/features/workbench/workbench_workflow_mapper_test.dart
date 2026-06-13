import 'package:cain_flow_mob/features/workbench/workbench_signals.dart';
import 'package:cain_flow_mob/features/workbench/workbench_workflow_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps the default workbench graph to a workflow document', () {
    final signals = WorkbenchSignals();

    final document = workbenchSignalsToWorkflow(signals);

    expect(document.nodes.length, 3);
    expect(document.connections.length, 2);

    final text = document.nodes.firstWhere((n) => n.id == 'node_text_prompt');
    expect(text.type, 'Text');
    expect(text.x, 80);
    expect(text.y, 120);
    expect(text.customTitle, 'Text Prompt');

    final connection = document.connections.firstWhere(
      (c) => c.id == 'conn_text_to_image',
    );
    expect(connection.from.nodeId, 'node_text_prompt');
    expect(connection.from.port, 'text');
    expect(connection.to.nodeId, 'node_image_generate');
    expect(connection.to.port, 'prompt');
    expect(connection.type, 'text');
  });

  test('omits customTitle when title equals the node type', () {
    final document = workbenchToWorkflow(
      nodes: const [
        WorkbenchNode(id: 'n', type: 'Text', title: 'Text', x: 0, y: 0),
      ],
      connections: const [],
    );

    expect(document.nodes.single.customTitle, isNull);
    expect(document.nodes.single.title, 'Text');
  });

  test('preserves pan and zoom in the canvas', () {
    final document = workbenchToWorkflow(
      nodes: const [],
      connections: const [],
      panOffset: const NodeOffset(12, -8),
      zoom: 1.5,
    );

    expect(document.canvas.x, 12);
    expect(document.canvas.y, -8);
    expect(document.canvas.zoom, 1.5);
  });
}
