import 'package:cain_flow_mob/features/workbench/workbench_signals.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('workbench graph state supports selection and node movement', () {
    final state = WorkbenchSignals();

    expect(state.nodeCount.value, 3);
    expect(state.connectionCount.value, 2);

    state.selectNode('node_image_generate');
    expect(state.selectedNodeId.value, 'node_image_generate');
    expect(state.selectedNode.value?.title, 'Image Generate');

    final before = state.selectedNode.value!;
    state.moveNode('node_image_generate', const NodeOffset(24, -8));
    final after = state.selectedNode.value!;

    expect(after.x, before.x + 24);
    expect(after.y, before.y - 8);
  });
}
