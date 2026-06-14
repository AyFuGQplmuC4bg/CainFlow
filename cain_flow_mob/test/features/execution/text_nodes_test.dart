import 'package:cain_flow_mob/core/models/flow_node.dart';
import 'package:cain_flow_mob/core/network/provider_client.dart';
import 'package:cain_flow_mob/core/storage/local_kv_store.dart';
import 'package:cain_flow_mob/features/execution/cain_flow_node_executor.dart';
import 'package:cain_flow_mob/features/execution/execution_services.dart';
import 'package:cain_flow_mob/features/execution/node_executor.dart';
import 'package:cain_flow_mob/features/execution/provider_request_builder.dart';
import 'package:cain_flow_mob/features/logs/log_signals.dart';
import 'package:cain_flow_mob/features/media/media_repository.dart';
import 'package:cain_flow_mob/features/settings/provider_settings.dart';
import 'package:flutter_test/flutter_test.dart';

NodeExecutionContext _context({Map<String, dynamic> inputs = const {}}) {
  return NodeExecutionContext(
    inputs: inputs,
    previousResults: const {},
    isCanceled: () => false,
  );
}

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

void main() {
  group('TextMerge', () {
    test('joins connected text inputs with the separator', () async {
      final node = const FlowNode(
        id: 'm',
        type: 'TextMerge',
        x: 0,
        y: 0,
        data: {'separator': ' / '},
      );
      final result = await _executor().execute(
        node,
        _context(inputs: {'text_1': 'a', 'text_2': 'b', 'text_3': 'c'}),
      );
      expect(result.outputs['text'], 'a / b / c');
    });

    test('skips empty inputs and unescapes \\n separator', () async {
      final node = const FlowNode(
        id: 'm',
        type: 'TextMerge',
        x: 0,
        y: 0,
        data: {'separator': r'\n'},
      );
      final result = await _executor().execute(
        node,
        _context(inputs: {'text_1': 'a', 'text_2': '', 'text_3': 'c'}),
      );
      expect(result.outputs['text'], 'a\nc');
    });
  });

  group('TextSplit', () {    test('splits input into part_1..3 by separator', () async {
      final node = const FlowNode(
        id: 's',
        type: 'TextSplit',
        x: 0,
        y: 0,
        data: {'separator': ','},
      );
      final result = await _executor().execute(
        node,
        _context(inputs: {'text': 'one,two,three'}),
      );
      expect(result.outputs['part_1'], 'one');
      expect(result.outputs['part_2'], 'two');
      expect(result.outputs['part_3'], 'three');
    });

    test('pads missing parts with empty strings', () async {
      final node = const FlowNode(
        id: 's',
        type: 'TextSplit',
        x: 0,
        y: 0,
        data: {'separator': ','},
      );
      final result = await _executor().execute(
        node,
        _context(inputs: {'text': 'only'}),
      );
      expect(result.outputs['part_1'], 'only');
      expect(result.outputs['part_2'], '');
      expect(result.outputs['part_3'], '');
    });
  });

  group('CameraControl', () {
    test('generates a viewpoint prompt from 5D params', () async {
      final node = const FlowNode(
        id: 'cam',
        type: 'CameraControl',
        x: 0,
        y: 0,
        data: {'pitch': 45.0, 'yaw': 90.0, 'distance': 2.0, 'fov': 20.0, 'roll': 0.0},
      );
      final result = await _executor().execute(node, _context());
      final text = result.outputs['text'] as String;
      expect(text, contains('Camera-only transformation'));
      expect(text, contains('high-angle'));
      expect(text, contains('right side'));
      expect(text, contains('extreme close-up'));
      expect(text, contains('super-telephoto'));
    });

    test('uses defaults when no params set (front view)', () async {
      final node = const FlowNode(id: 'cam', type: 'CameraControl', x: 0, y: 0);
      final result = await _executor().execute(node, _context());
      expect(
        result.outputs['text'] as String,
        contains('front three-quarter view'),
      );
    });
  });
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
