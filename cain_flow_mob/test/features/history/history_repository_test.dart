import 'package:cain_flow_mob/core/storage/local_kv_store.dart';
import 'package:cain_flow_mob/features/history/history_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  HistoryEntry entry(String id) {
    return HistoryEntry(
      id: id,
      workflowName: 'WF',
      createdAt: DateTime.utc(2026, 1, 1),
      durationMillis: 1234,
      stage: const StageSummary(
        label: 'Render',
        kind: 'image-generate',
        nodeCount: 3,
        keyNodeTitles: ['Text Prompt', 'Image Generate'],
      ),
      prompt: 'a cat',
      outputs: [
        const RunOutput(
          id: 'out_$id',
          kind: RunOutputKind.image,
          nodeId: 'node_$id',
          nodeTitle: 'Image Generate',
          relativePath: 'workflows/demo/media/$id.png',
          thumbnailRelativePath: 'workflows/demo/media/thumb_$id.png',
          url: 'https://cdn/$id.png',
        ),
        const RunOutput(
          id: 'txt_$id',
          kind: RunOutputKind.text,
          nodeId: 'node_text_$id',
          nodeTitle: 'Text Prompt',
          text: 'result $id',
        ),
      ],
      resultUrl: 'https://cdn/$id.png',
    );
  }

  test('add prepends newest-first and round-trips through storage', () {
    final repo = HistoryRepository(store: _MemStore());
    repo.add(entry('a'));
    repo.add(entry('b'));
    final all = repo.loadAll();
    expect(all.first.id, 'b');
    expect(all.last.id, 'a');
    expect(all.first.prompt, 'a cat');
    expect(all.first.stage?.label, 'Render');
    expect(all.first.outputs.length, 2);
    expect(all.first.outputs.first.kind, RunOutputKind.image);
    expect(all.first.outputs.last.kind, RunOutputKind.text);
  });

  test('trims to capacity', () {
    final repo = HistoryRepository(store: _MemStore(), capacity: 2);
    repo.add(entry('a'));
    repo.add(entry('b'));
    repo.add(entry('c'));
    final all = repo.loadAll();
    expect(all.length, 2);
    expect(all.map((e) => e.id), ['c', 'b']);
  });

  test('remove drops by id', () {
    final repo = HistoryRepository(store: _MemStore());
    repo.add(entry('a'));
    repo.add(entry('b'));
    repo.remove('a');
    expect(repo.loadAll().map((e) => e.id), ['b']);
  });

  test('malformed JSON yields empty list', () {
    final store = _MemStore()..setString('history:ring', '{not json');
    expect(HistoryRepository(store: store).loadAll(), isEmpty);
  });

  test('legacy record still loads an image output pointer', () {
    final store = _MemStore()
      ..setString(
        'history:ring',
        '[{"id":"x","workflowName":"WF","createdAt":"2026-01-01T00:00:00.000Z","resultUrl":"https://cdn/x.png"}]',
      );
    final all = HistoryRepository(store: store).loadAll();
    expect(all, hasLength(1));
    expect(all.single.outputs, hasLength(1));
    expect(all.single.outputs.single.kind, RunOutputKind.image);
    expect(all.single.outputs.single.url, 'https://cdn/x.png');
  });
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
