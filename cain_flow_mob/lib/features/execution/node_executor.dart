import '../../core/models/flow_connection.dart';
import '../../core/models/flow_node.dart';

abstract interface class NodeExecutor {
  Future<NodeExecutionResult> execute(
    FlowNode node,
    NodeExecutionContext context,
  );
}

class NodeExecutionContext {
  const NodeExecutionContext({
    required this.inputs,
    required this.previousResults,
    required this.isCanceled,
  });

  final Map<String, dynamic> inputs;
  final Map<String, NodeExecutionResult> previousResults;
  final bool Function() isCanceled;
}

class NodeExecutionResult {
  const NodeExecutionResult({
    required this.nodeId,
    required this.outputs,
    this.message = '',
  });

  factory NodeExecutionResult.empty(String nodeId) {
    return NodeExecutionResult(nodeId: nodeId, outputs: const {});
  }

  final String nodeId;
  final Map<String, dynamic> outputs;
  final String message;
}

Map<String, dynamic> collectNodeInputs({
  required FlowNode node,
  required List<FlowConnection> incomingConnections,
  required Map<String, NodeExecutionResult> previousResults,
}) {
  final inputs = <String, dynamic>{};
  for (final connection in incomingConnections) {
    final result = previousResults[connection.from.nodeId];
    if (result == null) continue;
    final output = result.outputs[connection.from.port];
    if (output != null) inputs[connection.to.port] = output;
  }
  return inputs;
}
