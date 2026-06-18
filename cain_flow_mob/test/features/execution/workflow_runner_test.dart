import 'dart:async';

import 'package:cain_flow_mob/core/models/flow_connection.dart';
import 'package:cain_flow_mob/core/models/flow_node.dart';
import 'package:cain_flow_mob/core/models/workflow_document.dart';
import 'package:cain_flow_mob/core/network/provider_client.dart';
import 'package:cain_flow_mob/features/execution/execution_signals.dart';
import 'package:cain_flow_mob/features/execution/node_executor.dart';
import 'package:cain_flow_mob/features/execution/workflow_runner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('runs nodes serially and passes upstream outputs to inputs', () async {
    final signals = ExecutionSignals();
    final executor = _FakeNodeExecutor(
      onExecute: (node, context) async {
        if (node.id == 'prompt') {
          return const NodeExecutionResult(
            nodeId: 'prompt',
            outputs: {'text': 'A lamp'},
          );
        }
        return NodeExecutionResult(
          nodeId: node.id,
          outputs: {'image': 'generated:${context.inputs['prompt']}'},
        );
      },
    );
    final runner = WorkflowRunner(executor: executor, signals: signals);

    final result = await runner.run(
      _workflow(
        nodes: const [
          FlowNode(id: 'prompt', type: 'Text', x: 0, y: 0),
          FlowNode(id: 'image', type: 'ImageGenerate', x: 0, y: 0),
        ],
        connections: [
          _connection('prompt_image', 'prompt', 'text', 'image', 'prompt'),
        ],
      ),
    );

    expect(result.state, WorkflowExecutionState.completed);
    expect(executor.calls, ['prompt', 'image']);
    expect(result.results['image']?.outputs['image'], 'generated:A lamp');
    expect(signals.workflowState.value, WorkflowExecutionState.completed);
    expect(signals.nodeStates.value['image']?.state, NodeRunState.completed);
  });

  test('marks failed node and skips downstream nodes', () async {
    final signals = ExecutionSignals();
    final executor = _FakeNodeExecutor(
      onExecute: (node, context) async {
        if (node.id == 'image') throw StateError('provider failed');
        return NodeExecutionResult.empty(node.id);
      },
    );
    final runner = WorkflowRunner(executor: executor, signals: signals);

    final result = await runner.run(
      _workflow(
        nodes: const [
          FlowNode(id: 'prompt', type: 'Text', x: 0, y: 0),
          FlowNode(id: 'image', type: 'ImageGenerate', x: 0, y: 0),
          FlowNode(id: 'save', type: 'ImageSave', x: 0, y: 0),
        ],
        connections: [
          _connection('prompt_image', 'prompt', 'text', 'image', 'prompt'),
          _connection('image_save', 'image', 'image', 'save', 'image'),
        ],
      ),
    );

    expect(result.state, WorkflowExecutionState.failed);
    expect(signals.nodeStates.value['image']?.state, NodeRunState.failed);
    expect(signals.nodeStates.value['save']?.state, NodeRunState.skipped);
    expect(signals.lastError.value, contains('provider failed'));
  });

  test('supports cancellation between serial nodes', () async {
    final signals = ExecutionSignals();
    late WorkflowRunner runner;
    final firstNodeStarted = Completer<void>();
    final releaseFirstNode = Completer<void>();
    final executor = _FakeNodeExecutor(
      onExecute: (node, context) async {
        firstNodeStarted.complete();
        await releaseFirstNode.future;
        return NodeExecutionResult.empty(node.id);
      },
    );
    runner = WorkflowRunner(executor: executor, signals: signals);

    final future = runner.run(
      _workflow(
        nodes: const [
          FlowNode(id: 'a', type: 'Text', x: 0, y: 0),
          FlowNode(id: 'b', type: 'TextChat', x: 0, y: 0),
        ],
        connections: [_connection('ab', 'a', 'text', 'b', 'prompt')],
      ),
    );
    await firstNodeStarted.future;
    runner.cancel();
    releaseFirstNode.complete();

    final result = await future;

    expect(result.state, WorkflowExecutionState.canceled);
    expect(executor.calls, ['a']);
    expect(signals.workflowState.value, WorkflowExecutionState.canceled);
    expect(signals.nodeStates.value['a']?.state, NodeRunState.skipped);
    expect(signals.nodeStates.value['b']?.state, NodeRunState.skipped);
  });

  test('treats provider request cancellation as canceled', () async {
    final signals = ExecutionSignals();
    final executor = _FakeNodeExecutor(
      onExecute: (node, context) async {
        throw const ProviderRequestCanceled();
      },
    );
    final runner = WorkflowRunner(executor: executor, signals: signals);

    final result = await runner.run(
      _workflow(
        nodes: const [FlowNode(id: 'a', type: 'TextChat', x: 0, y: 0)],
        connections: const [],
      ),
    );

    expect(result.state, WorkflowExecutionState.canceled);
    expect(signals.workflowState.value, WorkflowExecutionState.canceled);
    expect(signals.nodeStates.value['a']?.state, NodeRunState.skipped);
  });

  group('concurrent execution', () {
    test('runs independent nodes in parallel up to the limit', () async {
      final signals = ExecutionSignals();
      var active = 0;
      var peak = 0;
      final executor = _FakeNodeExecutor(
        onExecute: (node, context) async {
          active += 1;
          if (active > peak) peak = active;
          await Future<void>.delayed(const Duration(milliseconds: 30));
          active -= 1;
          return NodeExecutionResult.empty(node.id);
        },
      );
      final runner = WorkflowRunner(
        executor: executor,
        signals: signals,
        maxConcurrency: 3,
      );

      // Three independent source nodes feeding one sink.
      final result = await runner.run(
        _workflow(
          nodes: const [
            FlowNode(id: 'a', type: 'Text', x: 0, y: 0),
            FlowNode(id: 'b', type: 'Text', x: 0, y: 0),
            FlowNode(id: 'c', type: 'Text', x: 0, y: 0),
            FlowNode(id: 'sink', type: 'TextMerge', x: 0, y: 0),
          ],
          connections: [
            _connection('a_s', 'a', 'text', 'sink', 'text_1'),
            _connection('b_s', 'b', 'text', 'sink', 'text_2'),
            _connection('c_s', 'c', 'text', 'sink', 'text_3'),
          ],
        ),
      );

      expect(result.state, WorkflowExecutionState.completed);
      expect(peak, greaterThan(1));
      // Sink runs only after its three deps.
      expect(executor.calls.last, 'sink');
    });

    test('a failure in a parallel batch fails the workflow', () async {
      final signals = ExecutionSignals();
      final executor = _FakeNodeExecutor(
        onExecute: (node, context) async {
          if (node.id == 'b') throw StateError('boom');
          return NodeExecutionResult.empty(node.id);
        },
      );
      final runner = WorkflowRunner(
        executor: executor,
        signals: signals,
        maxConcurrency: 3,
      );

      final result = await runner.run(
        _workflow(
          nodes: const [
            FlowNode(id: 'a', type: 'Text', x: 0, y: 0),
            FlowNode(id: 'b', type: 'Text', x: 0, y: 0),
          ],
          connections: const [],
        ),
      );

      expect(result.state, WorkflowExecutionState.failed);
      expect(signals.nodeStates.value['b']?.state, NodeRunState.failed);
    });
  });
}

class _FakeNodeExecutor implements NodeExecutor {
  _FakeNodeExecutor({required this.onExecute});

  final Future<NodeExecutionResult> Function(
    FlowNode node,
    NodeExecutionContext context,
  )
  onExecute;
  final calls = <String>[];

  @override
  Future<NodeExecutionResult> execute(
    FlowNode node,
    NodeExecutionContext context,
  ) async {
    calls.add(node.id);
    return onExecute(node, context);
  }
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
