import 'package:cain_flow_mob/features/workbench/workbench_history.dart';
import 'package:cain_flow_mob/features/workbench/workbench_signals.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late WorkbenchSignals workbench;
  late WorkbenchHistory history;

  setUp(() {
    workbench = WorkbenchSignals();
    history = WorkbenchHistory(workbench: workbench);
    workbench.onBeforeMutation = history.record;
  });

  test('undo restores the graph before an add', () {
    final before = workbench.nodes.value.length;
    workbench.addNode('Text');
    expect(workbench.nodes.value.length, before + 1);
    expect(history.canUndo.value, isTrue);

    history.undo();
    expect(workbench.nodes.value.length, before);
    expect(history.canRedo.value, isTrue);
  });

  test('redo reapplies an undone change', () {
    workbench.addNode('Text');
    final afterAdd = workbench.nodes.value.length;
    history.undo();
    history.redo();
    expect(workbench.nodes.value.length, afterAdd);
  });

  test('a new mutation clears the redo stack', () {
    workbench.addNode('Text');
    history.undo();
    expect(history.canRedo.value, isTrue);
    workbench.addNode('TextChat');
    expect(history.canRedo.value, isFalse);
  });

  test('undo restores a removed node and its connections', () {
    final nodeCount = workbench.nodes.value.length;
    final connCount = workbench.connections.value.length;
    workbench.removeNode('node_image_generate');
    expect(workbench.nodes.value.length, lessThan(nodeCount));

    history.undo();
    expect(workbench.nodes.value.length, nodeCount);
    expect(workbench.connections.value.length, connCount);
  });

  test('undo of data edit restores prior params', () {
    workbench.updateNodeData('node_text_prompt', {'text': 'first'});
    workbench.updateNodeData('node_text_prompt', {'text': 'second'});
    history.undo();
    final node =
        workbench.nodes.value.firstWhere((n) => n.id == 'node_text_prompt');
    expect(node.data['text'], 'first');
  });

  test('undo/redo do not self-record onto the stacks', () {
    workbench.addNode('Text');
    history.undo();
    history.redo();
    history.undo();
    // After one add and balanced undo/redo, exactly one undo step remains
    // consumed; redo should be available, undo empty.
    expect(history.canUndo.value, isFalse);
    expect(history.canRedo.value, isTrue);
  });
}
