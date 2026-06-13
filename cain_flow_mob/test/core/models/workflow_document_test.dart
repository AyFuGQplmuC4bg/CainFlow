import 'package:cain_flow_mob/core/models/workflow_document.dart';
import 'package:cain_flow_mob/core/storage/local_kv_store.dart';
import 'package:cain_flow_mob/features/workflow/workflow_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('decodes and encodes a minimal CainFlow workflow document', () {
    final document = WorkflowDocument.fromJson({
      'canvas': {'x': 12.5, 'y': -4, 'zoom': 0.85},
      'version': '1.3',
      'nodes': [
        {
          'id': 'node_text',
          'type': 'Text',
          'x': 100,
          'y': 120,
          'customTitle': 'Prompt',
          'data': {'text': 'A quiet studio'},
          'legacyFlag': true,
        },
      ],
      'connections': [
        {
          'id': 'conn_1',
          'type': 'text',
          'from': {'nodeId': 'node_text', 'port': 'text', 'type': 'text'},
          'to': {'nodeId': 'node_image', 'port': 'prompt', 'type': 'text'},
        },
      ],
    });

    expect(document.version, '1.3');
    expect(document.canvas.x, 12.5);
    expect(document.canvas.y, -4);
    expect(document.canvas.zoom, 0.85);
    expect(document.nodes.single.id, 'node_text');
    expect(document.nodes.single.type, 'Text');
    expect(document.nodes.single.data['text'], 'A quiet studio');
    expect(document.nodes.single.extra['legacyFlag'], true);
    expect(document.connections.single.from.nodeId, 'node_text');

    final encoded = document.toJson();
    expect(encoded['version'], '1.3');
    expect((encoded['nodes'] as List).single['legacyFlag'], true);
    expect((encoded['connections'] as List).single['from']['port'], 'text');
  });

  test('workflow repository saves and loads documents through LocalKvStore', () {
    final store = _MemoryLocalKvStore();
    final repository = WorkflowRepository(store: store);
    final document = WorkflowDocument.empty();

    repository.saveWorkflow('wf_demo', document);

    expect(repository.listWorkflowIds(), ['wf_demo']);
    expect(repository.loadWorkflow('wf_demo')?.version, document.version);
  });
}

class _MemoryLocalKvStore implements LocalKvStore {
  final Map<String, Object> _values = {};

  @override
  bool containsKey(String key) => _values.containsKey(key);

  @override
  bool getBool(String key, {bool defaultValue = false}) {
    return _values[key] as bool? ?? defaultValue;
  }

  @override
  int getInt(String key, {int defaultValue = 0}) {
    return _values[key] as int? ?? defaultValue;
  }

  @override
  String? getString(String key) => _values[key] as String?;

  @override
  void remove(String key) {
    _values.remove(key);
  }

  @override
  bool setBool(String key, bool value) {
    _values[key] = value;
    return true;
  }

  @override
  bool setInt(String key, int value) {
    _values[key] = value;
    return true;
  }

  @override
  bool setString(String key, String value) {
    _values[key] = value;
    return true;
  }
}
