import 'package:signals/signals.dart';

enum WorkflowExecutionState { idle, running, completed, failed, canceled }

enum NodeRunState { pending, running, completed, failed, skipped }

class NodeRunSnapshot {
  const NodeRunSnapshot({required this.state, this.message = ''});

  final NodeRunState state;
  final String message;
}

class ExecutionSignals {
  ExecutionSignals();

  final workflowState = signal(WorkflowExecutionState.idle);
  final activeNodeId = signal<String?>(null);
  final nodeStates = signal<Map<String, NodeRunSnapshot>>(const {});
  final lastError = signal<String>('');

  /// Latest image output payload per node id (`{kind: url|asset, ...}`),
  /// used to render canvas thumbnails after a run.
  final imageOutputs = signal<Map<String, Map<String, dynamic>>>(const {});

  late final isRunning = computed(
    () => workflowState.value == WorkflowExecutionState.running,
  );

  void reset(Iterable<String> nodeIds) {
    workflowState.value = WorkflowExecutionState.idle;
    activeNodeId.value = null;
    lastError.value = '';
    imageOutputs.value = const {};
    nodeStates.value = {
      for (final id in nodeIds)
        id: const NodeRunSnapshot(state: NodeRunState.pending),
    };
  }

  /// Records an image output payload for [nodeId] for canvas previews.
  void setImageOutput(String nodeId, Map<String, dynamic> payload) {
    imageOutputs.value = {...imageOutputs.value, nodeId: payload};
  }

  void markWorkflowRunning() {
    workflowState.value = WorkflowExecutionState.running;
    lastError.value = '';
  }

  void markNode(String nodeId, NodeRunState state, {String message = ''}) {
    nodeStates.value = {
      ...nodeStates.value,
      nodeId: NodeRunSnapshot(state: state, message: message),
    };
    activeNodeId.value = state == NodeRunState.running ? nodeId : null;
  }

  void markWorkflowCompleted() {
    workflowState.value = WorkflowExecutionState.completed;
    activeNodeId.value = null;
  }

  void markWorkflowFailed(String message) {
    workflowState.value = WorkflowExecutionState.failed;
    activeNodeId.value = null;
    lastError.value = message;
  }

  void markWorkflowCanceled() {
    workflowState.value = WorkflowExecutionState.canceled;
    activeNodeId.value = null;
  }
}

/// Shared execution signals used by the default workbench controller and the
/// canvas/inspector status widgets.
final executionSignals = ExecutionSignals();
