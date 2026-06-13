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

  test('node data round-trips through JSON and survives moveBy', () {
    const node = WorkbenchNode(
      id: 'n1',
      type: 'TextChat',
      title: 'Chat',
      x: 10,
      y: 20,
      data: {'apiConfigId': 'm1', 'systemPrompt': 'be brief'},
    );

    final restored = WorkbenchNode.fromJson(node.toJson());
    expect(restored.data['apiConfigId'], 'm1');
    expect(restored.data['systemPrompt'], 'be brief');

    final moved = node.moveBy(const NodeOffset(5, 5));
    expect(moved.data['apiConfigId'], 'm1');
  });

  test('updateNodeData replaces the parameter map', () {
    final state = WorkbenchSignals();
    state.updateNodeData('node_text_prompt', {'text': 'hello'});
    final node =
        state.nodes.value.firstWhere((n) => n.id == 'node_text_prompt');
    expect(node.data['text'], 'hello');
  });

  test('toJson omits empty data', () {
    const node = WorkbenchNode(id: 'n', type: 'Text', title: 'T', x: 0, y: 0);
    expect(node.toJson().containsKey('data'), isFalse);
  });
}
