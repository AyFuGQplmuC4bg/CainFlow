import 'dart:async';

import 'package:signals/signals.dart';

enum WorkflowExecutionState { idle, running, completed, failed, canceled }

enum NodeRunState { pending, running, completed, failed, skipped }

class NodeRunSnapshot {
  const NodeRunSnapshot({
    required this.state,
    this.message = '',
    this.startedAt,
    this.finishedAt,
  });

  final NodeRunState state;
  final String message;
  final DateTime? startedAt;
  final DateTime? finishedAt;

  /// Elapsed time for this node. While running, measured against [now];
  /// for terminal states, the fixed [startedAt]–[finishedAt] interval.
  Duration? durationAt(DateTime now) {
    if (startedAt == null) return null;
    final end = finishedAt ?? now;
    final d = end.difference(startedAt!);
    return d.isNegative ? Duration.zero : d;
  }
}

class ExecutionSignals {
  ExecutionSignals({DateTime Function()? now, this.onEvent})
    : _now = now ?? DateTime.now;

  final DateTime Function() _now;
  void Function(Map<String, dynamic> event)? onEvent;

  final workflowState = signal(WorkflowExecutionState.idle);
  final activeNodeId = signal<String?>(null);
  final nodeStates = signal<Map<String, NodeRunSnapshot>>(const {});
  final lastError = signal<String>('');
  final workflowStartedAt = signal<DateTime?>(null);

  /// Latest image output payload per node id (`{kind: url|asset, ...}`),
  /// used to render canvas thumbnails after a run.
  final imageOutputs = signal<Map<String, Map<String, dynamic>>>(const {});

  /// Transient per-node progress text (e.g. async polling "轮询 3"), cleared
  /// when the node reaches a terminal state.
  final pollProgress = signal<Map<String, String>>(const {});
  final backgroundJobId = signal<String>('');

  /// Ticks once per second while a workflow is running, so widgets reading a
  /// running node's elapsed time rebuild and show live seconds. Idle between
  /// runs (the timer is stopped) to avoid a permanent wakeup.
  final nowTick = signal<DateTime>(DateTime.fromMillisecondsSinceEpoch(0));
  Timer? _ticker;

  late final isRunning = computed(
    () => workflowState.value == WorkflowExecutionState.running,
  );

  late final totalCount = computed(() => nodeStates.value.length);
  late final completedCount = computed(
    () => nodeStates.value.values
        .where((s) => s.state == NodeRunState.completed)
        .length,
  );

  void reset(Iterable<String> nodeIds) {
    final activeBackgroundJob = backgroundJobId.value;
    workflowState.value = WorkflowExecutionState.idle;
    activeNodeId.value = null;
    lastError.value = '';
    imageOutputs.value = const {};
    pollProgress.value = const {};
    backgroundJobId.value = activeBackgroundJob;
    workflowStartedAt.value = null;
    nodeStates.value = {
      for (final id in nodeIds)
        id: const NodeRunSnapshot(state: NodeRunState.pending),
    };
    _emit('reset', payload: {'nodeIds': nodeIds.toList()});
  }

  /// Records an image output payload for [nodeId] for canvas previews.
  void setImageOutput(String nodeId, Map<String, dynamic> payload) {
    imageOutputs.value = {...imageOutputs.value, nodeId: payload};
    _emit('image_output', nodeId: nodeId, payload: payload);
  }

  /// Sets transient progress text for a running node (async polling, etc.).
  void setPollProgress(String nodeId, String text) {
    pollProgress.value = {...pollProgress.value, nodeId: text};
    _emit('poll_progress', nodeId: nodeId, message: text);
  }

  void markWorkflowRunning() {
    workflowState.value = WorkflowExecutionState.running;
    lastError.value = '';
    workflowStartedAt.value = _now();
    _startTicker();
    _emit('started');
  }

  void markNode(String nodeId, NodeRunState state, {String message = ''}) {
    final previous = nodeStates.value[nodeId];
    final now = _now();
    final startedAt = state == NodeRunState.running ? now : previous?.startedAt;
    final finishedAt = switch (state) {
      NodeRunState.completed ||
      NodeRunState.failed ||
      NodeRunState.skipped => now,
      _ => null,
    };
    nodeStates.value = {
      ...nodeStates.value,
      nodeId: NodeRunSnapshot(
        state: state,
        message: message,
        startedAt: startedAt,
        finishedAt: finishedAt,
      ),
    };
    activeNodeId.value = state == NodeRunState.running ? nodeId : null;

    // Clear transient progress when leaving the running state.
    if (state != NodeRunState.running &&
        pollProgress.value.containsKey(nodeId)) {
      final next = Map<String, String>.from(pollProgress.value)..remove(nodeId);
      pollProgress.value = next;
    }

    _emit(
      switch (state) {
        NodeRunState.running => 'node_running',
        NodeRunState.completed => 'node_completed',
        NodeRunState.failed => 'node_failed',
        NodeRunState.skipped => 'node_skipped',
        NodeRunState.pending => 'node_pending',
      },
      nodeId: nodeId,
      message: message,
    );
  }

  void markWorkflowCompleted() {
    workflowState.value = WorkflowExecutionState.completed;
    activeNodeId.value = null;
    _stopTicker();
    _emit('completed');
  }

  void markWorkflowFailed(String message) {
    workflowState.value = WorkflowExecutionState.failed;
    activeNodeId.value = null;
    lastError.value = message;
    _stopTicker();
    _emit('failed', message: message);
  }

  void markWorkflowCanceled() {
    workflowState.value = WorkflowExecutionState.canceled;
    activeNodeId.value = null;
    _stopTicker();
    _emit('canceled');
  }

  /// Total elapsed workflow time, measured against the live tick while running.
  Duration? workflowElapsedAt(DateTime now) {
    final start = workflowStartedAt.value;
    if (start == null) return null;
    final d = now.difference(start);
    return d.isNegative ? Duration.zero : d;
  }

  void _startTicker() {
    nowTick.value = _now();
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      nowTick.value = _now();
    });
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
    nowTick.value = _now();
  }

  /// Stops the timer; call when disposing in tests.
  void dispose() => _stopTicker();

  void _emit(
    String type, {
    String nodeId = '',
    String message = '',
    double progress = 0,
    Map<String, dynamic> payload = const {},
  }) {
    final handler = onEvent;
    if (handler == null) return;
    final nextPayload = <String, dynamic>{
      if (nodeId.isNotEmpty) 'nodeId': nodeId,
      ...payload,
    };
    handler({
      'type': type,
      'jobId': backgroundJobId.value,
      if (message.isNotEmpty) 'message': message,
      if (progress > 0) 'progress': progress,
      if (nextPayload.isNotEmpty) 'payload': nextPayload,
    });
  }
}

/// Shared execution signals used by the default workbench controller and the
/// canvas/inspector status widgets.
final executionSignals = ExecutionSignals();
