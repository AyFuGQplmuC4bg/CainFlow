import 'package:cain_flow_mob/core/models/flow_node.dart';
import 'package:cain_flow_mob/core/models/workflow_document.dart';
import 'package:cain_flow_mob/features/workflow/workflow_archive.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('exports and imports workflow archives', () {
    final archive = WorkflowArchive(
      name: 'Demo',
      document: WorkflowDocument(
        canvas: WorkflowCanvas.empty(),
        nodes: const [FlowNode(id: 'text', type: 'Text', x: 1, y: 2)],
        connections: const [],
        version: WorkflowDocument.defaultVersion,
      ),
    );

    final source = exportWorkflowArchive(archive);
    final restored = importWorkflowArchive(source);

    expect(restored.name, 'Demo');
    expect(restored.document.nodes.single.id, 'text');
  });
}
