import 'package:cain_flow_mob/core/storage/local_kv_store.dart';
import 'package:cain_flow_mob/features/prompts/prompt_library.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('add inserts newest-first and persists', () {
    final lib = PromptLibrary(store: _MemStore());
    lib.add('First', 'body one');
    final second = lib.add('Second', 'body two');
    final all = lib.loadAll();
    expect(all.first.id, second.id);
    expect(all.first.title, 'Second');
    expect(all.length, 2);
  });

  test('blank title falls back to Untitled', () {
    final lib = PromptLibrary(store: _MemStore());
    final t = lib.add('   ', 'x');
    expect(t.title, 'Untitled');
  });

  test('update edits title/body in place', () {
    final lib = PromptLibrary(store: _MemStore());
    final t = lib.add('Old', 'old body');
    lib.update(t.id, title: 'New', body: 'new body');
    final updated = lib.loadAll().single;
    expect(updated.title, 'New');
    expect(updated.body, 'new body');
    expect(updated.id, t.id);
  });

  test('remove deletes by id', () {
    final lib = PromptLibrary(store: _MemStore());
    final a = lib.add('A', '1');
    lib.add('B', '2');
    lib.remove(a.id);
    expect(lib.loadAll().map((t) => t.title), ['B']);
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
