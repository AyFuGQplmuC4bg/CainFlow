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

  late final isRunning = computed(
    () => workflowState.value == WorkflowExecutionState.running,
  );

  void reset(Iterable<String> nodeIds) {
    workflowState.value = WorkflowExecutionState.idle;
    activeNodeId.value = null;
    lastError.value = '';
    nodeStates.value = {
      for (final id in nodeIds)
        id: const NodeRunSnapshot(state: NodeRunState.pending),
    };
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
