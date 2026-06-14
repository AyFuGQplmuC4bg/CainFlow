import 'package:cain_flow_mob/features/execution/execution_signals.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Fixed, advancing clock for deterministic durations.
  late DateTime clock;
  ExecutionSignals make() => ExecutionSignals(now: () => clock);

  setUp(() => clock = DateTime.utc(2026, 6, 14, 12, 0, 0));

  test('markNode stamps startedAt on running and finishedAt on completion', () {
    final signals = make();
    signals.reset(const ['a']);

    clock = DateTime.utc(2026, 6, 14, 12, 0, 1);
    signals.markNode('a', NodeRunState.running);
    final running = signals.nodeStates.value['a']!;
    expect(running.startedAt, clock);
    expect(running.finishedAt, isNull);

    clock = DateTime.utc(2026, 6, 14, 12, 0, 4);
    signals.markNode('a', NodeRunState.completed);
    final done = signals.nodeStates.value['a']!;
    expect(done.startedAt, DateTime.utc(2026, 6, 14, 12, 0, 1));
    expect(done.finishedAt, clock);
    expect(done.durationAt(clock), const Duration(seconds: 3));

    signals.dispose();
  });

  test('running duration grows with the supplied now', () {
    final signals = make();
    signals.reset(const ['a']);
    signals.markNode('a', NodeRunState.running);
    final snap = signals.nodeStates.value['a']!;
    expect(
      snap.durationAt(clock.add(const Duration(seconds: 5))),
      const Duration(seconds: 5),
    );
    signals.dispose();
  });

  test('completedCount and totalCount reflect node states', () {
    final signals = make();
    signals.reset(const ['a', 'b', 'c']);
    expect(signals.totalCount.value, 3);
    expect(signals.completedCount.value, 0);
    signals.markNode('a', NodeRunState.completed);
    signals.markNode('b', NodeRunState.completed);
    expect(signals.completedCount.value, 2);
    signals.dispose();
  });

  test('pollProgress is set and cleared on terminal state', () {
    final signals = make();
    signals.reset(const ['a']);
    signals.markNode('a', NodeRunState.running);
    signals.setPollProgress('a', '轮询 3');
    expect(signals.pollProgress.value['a'], '轮询 3');

    signals.markNode('a', NodeRunState.completed);
    expect(signals.pollProgress.value.containsKey('a'), isFalse);
    signals.dispose();
  });

  test('workflow elapsed measured from markWorkflowRunning', () {
    final signals = make();
    signals.reset(const ['a']);
    signals.markWorkflowRunning();
    expect(
      signals.workflowElapsedAt(clock.add(const Duration(seconds: 8))),
      const Duration(seconds: 8),
    );
    signals.dispose();
  });

  test('reset clears timing and progress state', () {
    final signals = make();
    signals.reset(const ['a']);
    signals.markWorkflowRunning();
    signals.markNode('a', NodeRunState.running);
    signals.setPollProgress('a', 'x');

    signals.reset(const ['a']);
    expect(signals.workflowStartedAt.value, isNull);
    expect(signals.pollProgress.value, isEmpty);
    expect(signals.nodeStates.value['a']!.startedAt, isNull);
    signals.dispose();
  });
}
