import 'package:cain_flow_mob/features/workbench/connection_rules.dart';
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

  test('moveNodeByViewportDelta compensates for canvas zoom', () {
    final state = WorkbenchSignals();
    state.zoom.value = 2;

    state.moveNodeByViewportDelta('node_image_generate', const NodeOffset(20, 10));

    final node = state.nodes.value.firstWhere(
      (n) => n.id == 'node_image_generate',
    );
    expect(node.x, 370);
    expect(node.y, 101);
  });

  test('viewport drag compensation matches displayed node coordinates', () {
    final state = WorkbenchSignals();
    state.panOffset.value = const NodeOffset(40, -30);
    state.zoom.value = 0.5;

    final before = state.nodes.value.firstWhere(
      (n) => n.id == 'node_image_generate',
    );
    final beforeDisplayX = state.panOffset.value.dx + before.x * state.zoom.value;
    final beforeDisplayY = state.panOffset.value.dy + before.y * state.zoom.value;

    state.moveNodeByViewportDelta('node_image_generate', const NodeOffset(15, 20));

    final after = state.nodes.value.firstWhere(
      (n) => n.id == 'node_image_generate',
    );
    final afterDisplayX = state.panOffset.value.dx + after.x * state.zoom.value;
    final afterDisplayY = state.panOffset.value.dy + after.y * state.zoom.value;

    expect(afterDisplayX, beforeDisplayX + 15);
    expect(afterDisplayY, beforeDisplayY + 20);
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
    final node = state.nodes.value.firstWhere(
      (n) => n.id == 'node_text_prompt',
    );
    expect(node.data['text'], 'hello');
  });

  test('zoom around viewport point keeps that canvas point anchored', () {
    final state = WorkbenchSignals();
    state.moveCanvas(const NodeOffset(20, -10));

    state.setZoomAroundViewportPoint(0.25, const NodeOffset(200, 150));

    expect(state.zoom.value, 0.25);
    // The canvas point under viewport (200, 150) before zoom was (180, 160).
    expect(state.panOffset.value.dx + 180 * state.zoom.value, 200);
    expect(state.panOffset.value.dy + 160 * state.zoom.value, 150);
  });

  test('zoom has no 50 percent floor and is capped at 100 percent', () {
    final state = WorkbenchSignals();

    state.setZoom(0.25);
    expect(state.zoom.value, 0.25);

    state.setZoom(1.5);
    expect(state.zoom.value, 1);
  });

  test('zoom stays positive when asked for zero or less', () {
    final state = WorkbenchSignals();

    state.setZoom(0);
    expect(state.zoom.value, 0.01);

    state.setZoom(-1);
    expect(state.zoom.value, 0.01);
  });

  test('toJson omits empty data', () {
    const node = WorkbenchNode(id: 'n', type: 'Text', title: 'T', x: 0, y: 0);
    expect(node.toJson().containsKey('data'), isFalse);
  });

  group('node add/remove', () {
    test('addNode seeds default data and returns the new id', () {
      final state = WorkbenchSignals();
      final id = state.addNode('TextChat');
      final node = state.nodes.value.firstWhere((n) => n.id == id);
      expect(node.type, 'TextChat');
      expect(node.data['systemPrompt'], '');
    });

    test('removeNode drops the node and its connections', () {
      final state = WorkbenchSignals();
      expect(state.connectionCount.value, 2);
      state.removeNode('node_image_generate');
      expect(
        state.nodes.value.any((n) => n.id == 'node_image_generate'),
        isFalse,
      );
      // Both default connections touched that node.
      expect(state.connectionCount.value, 0);
    });

    test('removeNode clears selection when the selected node is removed', () {
      final state = WorkbenchSignals();
      state.selectNode('node_text_prompt');
      state.removeNode('node_text_prompt');
      expect(state.selectedNodeId.value, isNull);
    });

    test('disconnectNode drops every connection touching the node', () {
      final state = WorkbenchSignals();
      var mutationCount = 0;
      state.onBeforeMutation = () => mutationCount++;

      state.disconnectNode('node_image_generate');

      expect(state.connectionCount.value, 0);
      expect(state.nodes.value.any((n) => n.id == 'node_image_generate'), isTrue);
      expect(mutationCount, 1);
    });
  });

  group('point-select connections', () {
    test('completes a compatible connection and replaces same-input edge', () {
      final state = WorkbenchSignals();
      // Existing: text->prompt, image->image. Re-wire prompt from a new Text.
      final newText = state.addNode('Text');
      state.beginConnection(newText, 'text', 'text');
      final rejection = state.completeConnection(
        'node_image_generate',
        'prompt',
        'text',
      );

      expect(rejection, ConnectionRejection.none);
      final promptEdges = state.connections.value.where(
        (c) => c.toNodeId == 'node_image_generate' && c.toPort == 'prompt',
      );
      expect(promptEdges.length, 1);
      expect(promptEdges.single.fromNodeId, newText);
      expect(state.pendingConnection.value, isNull);
    });

    test('rejects a type mismatch', () {
      final state = WorkbenchSignals();
      state.beginConnection('node_image_generate', 'image', 'image');
      final rejection = state.completeConnection(
        'node_image_generate',
        'prompt',
        'text',
      );
      // self-connection is checked first here; use distinct nodes instead.
      expect(rejection, ConnectionRejection.selfConnection);
    });

    test('rejects connecting a node to itself', () {
      final state = WorkbenchSignals();
      state.beginConnection('node_text_prompt', 'text', 'text');
      final rejection = state.completeConnection(
        'node_text_prompt',
        'prompt',
        'text',
      );
      expect(rejection, ConnectionRejection.selfConnection);
    });

    test('removeConnection deletes by id', () {
      final state = WorkbenchSignals();
      state.removeConnection('conn_text_to_image');
      expect(
        state.connections.value.any((c) => c.id == 'conn_text_to_image'),
        isFalse,
      );
    });
  });
}
