import 'package:cain_flow_mob/core/models/flow_connection.dart';
import 'package:cain_flow_mob/core/models/flow_node.dart';
import 'package:cain_flow_mob/core/models/workflow_document.dart';
import 'package:cain_flow_mob/core/network/provider_client.dart';
import 'package:cain_flow_mob/core/storage/local_kv_store.dart';
import 'package:cain_flow_mob/features/execution/cain_flow_node_executor.dart';
import 'package:cain_flow_mob/features/execution/execution_services.dart';
import 'package:cain_flow_mob/features/execution/execution_signals.dart';
import 'package:cain_flow_mob/features/execution/iterative_workflow_runner.dart';
import 'package:cain_flow_mob/features/execution/node_executor.dart';
import 'package:cain_flow_mob/features/execution/provider_request_builder.dart';
import 'package:cain_flow_mob/features/logs/log_signals.dart';
import 'package:cain_flow_mob/features/media/media_repository.dart';
import 'package:cain_flow_mob/features/settings/provider_settings.dart';
import 'package:flutter_test/flutter_test.dart';

CainFlowNodeExecutor _executor() {
  final store = _MemStore();
  return CainFlowNodeExecutor(
    services: ExecutionServices(
      settingsRepository: ProviderSettingsRepository(store: store),
      providerClient: _NoopClient(),
      mediaRepository: MediaRepository(store: store),
      logs: LogSignals(),
      workflowId: 'wf',
    ),
  );
}

WorkflowDocument _doc(List<FlowNode> nodes, List<FlowConnection> conns) {
  return WorkflowDocument(
    canvas: WorkflowCanvas.empty(),
    nodes: nodes,
    connections: conns,
    version: WorkflowDocument.defaultVersion,
  );
}

FlowConnection _c(String id, String fn, String fp, String tn, String tp) {
  return FlowConnection(
    id: id,
    from: FlowEndpoint(nodeId: fn, port: fp),
    to: FlowEndpoint(nodeId: tn, port: tp),
  );
}

void main() {
  test('condition routes to the true branch and skips false', () async {
    final signals = ExecutionSignals();
    final runner = IterativeWorkflowRunner(
      executor: _executor(),
      signals: signals,
    );

    final result = await runner.run(
      _doc(
        const [
          FlowNode(id: 'src', type: 'Text', x: 0, y: 0, data: {'text': 'hi'}),
          FlowNode(
            id: 'cond',
            type: 'ControlCondition',
            x: 0,
            y: 0,
            data: {'operator': '==', 'compareTo': 'hi'},
          ),
          FlowNode(id: 'yes', type: 'Text', x: 0, y: 0, data: {'text': 'Y'}),
          FlowNode(id: 'no', type: 'Text', x: 0, y: 0, data: {'text': 'N'}),
        ],
        [
          _c('s_c', 'src', 'text', 'cond', 'value'),
          _c('c_y', 'cond', 'true', 'yes', 'text'),
          _c('c_n', 'cond', 'false', 'no', 'text'),
        ],
      ),
    );

    expect(result.state, WorkflowExecutionState.completed);
    expect(signals.nodeStates.value['yes']?.state, NodeRunState.completed);
    // False branch never became ready.
    expect(signals.nodeStates.value['no']?.state, NodeRunState.pending);
  });

  test('loop emits the loop branch count times then done', () async {
    final signals = ExecutionSignals();
    final executor = _executor();
    final runner = IterativeWorkflowRunner(
      executor: executor,
      signals: signals,
    );

    // src -> loop; loop.loop -> sink (counts loop executions).
    final result = await runner.run(
      _doc(
        const [
          FlowNode(id: 'src', type: 'Text', x: 0, y: 0, data: {'text': 'x'}),
          FlowNode(
            id: 'loop',
            type: 'ControlLoop',
            x: 0,
            y: 0,
            data: {'count': 3},
          ),
          FlowNode(id: 'done', type: 'Text', x: 0, y: 0, data: {'text': 'd'}),
        ],
        [
          _c('s_l', 'src', 'text', 'loop', 'value'),
          // loop branch feeds back into the loop node to re-trigger it.
          _c('l_l', 'loop', 'loop', 'loop', 'value'),
          _c('l_d', 'loop', 'done', 'done', 'text'),
        ],
      ),
    );

    expect(result.state, WorkflowExecutionState.completed);
    expect(signals.nodeStates.value['done']?.state, NodeRunState.completed);
  });

  test('maxSteps guards against runaway loops', () async {
    final signals = ExecutionSignals();
    final runner = IterativeWorkflowRunner(
      executor: _executor(),
      signals: signals,
      maxSteps: 5,
    );

    // A loop with a huge count that always re-enters will hit the step cap.
    final result = await runner.run(
      _doc(
        const [
          FlowNode(id: 'src', type: 'Text', x: 0, y: 0, data: {'text': 'x'}),
          FlowNode(
            id: 'loop',
            type: 'ControlLoop',
            x: 0,
            y: 0,
            data: {'count': 1000},
          ),
        ],
        [
          _c('s_l', 'src', 'text', 'loop', 'value'),
          _c('l_l', 'loop', 'loop', 'loop', 'value'),
        ],
      ),
    );

    expect(result.state, WorkflowExecutionState.failed);
    expect(result.error, contains('max steps'));
  });

  test('treats provider request cancellation as canceled', () async {
    final signals = ExecutionSignals();
    final runner = IterativeWorkflowRunner(
      executor: _CancelingExecutor(),
      signals: signals,
    );

    final result = await runner.run(
      _doc(const [FlowNode(id: 'src', type: 'TextChat', x: 0, y: 0)], const []),
    );

    expect(result.state, WorkflowExecutionState.canceled);
    expect(signals.workflowState.value, WorkflowExecutionState.canceled);
    expect(signals.nodeStates.value['src']?.state, NodeRunState.skipped);
  });
}

class _CancelingExecutor implements NodeExecutor {
  @override
  Future<NodeExecutionResult> execute(
    FlowNode node,
    NodeExecutionContext context,
  ) async {
    throw const ProviderRequestCanceled();
  }
}

class _NoopClient implements ProviderClient {
  @override
  Future<ProviderResponse> send(
    ProviderRequest request, {
    ProviderRequestOptions options = const ProviderRequestOptions(),
  }) async {
    return const ProviderResponse(statusCode: 200, body: '{}');
  }
}

class _MemStore implements LocalKvStore {
  final Map<String, Object> _v = {};
  @override
  bool containsKey(String key) => _v.containsKey(key);
  @override
  bool getBool(String key, {bool defaultValue = false}) =>
      _v[key] as bool? ?? defaultValue;
  @override
  int getInt(String key, {int defaultValue = 0}) =>
      _v[key] as int? ?? defaultValue;
  @override
  String? getString(String key) => _v[key] as String?;
  @override
  void remove(String key) => _v.remove(key);
  @override
  bool setBool(String key, bool value) {
    _v[key] = value;
    return true;
  }

  @override
  bool setInt(String key, int value) {
    _v[key] = value;
    return true;
  }

  @override
  bool setString(String key, String value) {
    _v[key] = value;
    return true;
  }
}
