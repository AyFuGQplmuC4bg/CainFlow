import 'package:cain_flow_mob/core/models/flow_node.dart';
import 'package:cain_flow_mob/features/execution/node_executor.dart';
import 'package:cain_flow_mob/features/logs/log_signals.dart';
import 'package:cain_flow_mob/features/workbench/completion_feedback.dart';
import 'package:cain_flow_mob/features/workbench/workbench_execution_controller.dart';
import 'package:cain_flow_mob/features/workbench/workbench_signals.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Run drives the runner and returns workbench to idle on success', () async {
    final workbench = WorkbenchSignals();
    final logs = LogSignals();
    final feedback = _SpyFeedback();
    final controller = WorkbenchExecutionController(
      workbench: workbench,
      executor: _PassthroughExecutor(),
      logs: logs,
      feedback: feedback,
    );

    final result = await controller.run();

    expect(result, isNotNull);
    expect(workbench.runState.value, WorkbenchRunState.idle);
    expect(controller.isRunning, isFalse);
    expect(
      logs.entries.value.any((e) => e.message.contains('completed')),
      isTrue,
    );
    expect(feedback.successCount, 1);
    expect(feedback.failureCount, 0);
  });

  test('Stop cancels an in-flight run and marks workbench stopped', () async {
    final workbench = WorkbenchSignals();
    final logs = LogSignals();
    late WorkbenchExecutionController controller;
    controller = WorkbenchExecutionController(
      workbench: workbench,
      executor: _SlowExecutor(onFirstNode: () => controller.stop()),
      logs: logs,
      feedback: _SpyFeedback(),
    );

    final result = await controller.run();

    expect(workbench.runState.value, WorkbenchRunState.stopped);
    expect(result!.state.name, 'canceled');
    expect(
      logs.entries.value.any((e) => e.message.contains('canceled')),
      isTrue,
    );
  });

  test('does not start a second run while already running', () async {
    final workbench = WorkbenchSignals();
    final controller = WorkbenchExecutionController(
      workbench: workbench,
      executor: _PassthroughExecutor(),
      logs: LogSignals(),
      feedback: _SpyFeedback(),
    );

    final first = controller.run();
    final second = await controller.run();
    await first;

    expect(second, isNull);
  });
}

class _SpyFeedback implements CompletionFeedback {
  int successCount = 0;
  int failureCount = 0;

  @override
  Future<void> success() async => successCount++;

  @override
  Future<void> failure() async => failureCount++;
}

class _PassthroughExecutor implements NodeExecutor {
  @override
  Future<NodeExecutionResult> execute(
    FlowNode node,
    NodeExecutionContext context,
  ) async {
    return NodeExecutionResult(nodeId: node.id, outputs: const {});
  }
}

class _SlowExecutor implements NodeExecutor {
  _SlowExecutor({required this.onFirstNode});

  final void Function() onFirstNode;
  bool _firstHandled = false;

  @override
  Future<NodeExecutionResult> execute(
    FlowNode node,
    NodeExecutionContext context,
  ) async {
    if (!_firstHandled) {
      _firstHandled = true;
      onFirstNode();
    }
    return NodeExecutionResult(nodeId: node.id, outputs: const {});
  }
}
