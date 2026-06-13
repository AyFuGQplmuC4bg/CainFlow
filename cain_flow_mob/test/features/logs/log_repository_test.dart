import 'package:cain_flow_mob/core/storage/local_kv_store.dart';
import 'package:cain_flow_mob/core/storage/storage_keys.dart';
import 'package:cain_flow_mob/features/logs/log_repository.dart';
import 'package:cain_flow_mob/features/logs/log_signals.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('round-trips log entries through storage', () {
    final store = _MemoryLocalKvStore();
    final repository = LogRepository(store: store);
    final entries = [
      LogEntry(
        id: '2',
        level: LogLevel.error,
        message: 'boom',
        createdAt: DateTime.utc(2026, 6, 13, 10, 30),
        scope: 'TextChat',
      ),
      LogEntry(
        id: '1',
        level: LogLevel.info,
        message: 'started',
        createdAt: DateTime.utc(2026, 6, 13, 10, 29),
      ),
    ];

    expect(repository.save(entries), isTrue);
    final restored = repository.load();

    expect(restored.map((e) => e.id), ['2', '1']);
    expect(restored.first.level, LogLevel.error);
    expect(restored.first.scope, 'TextChat');
    expect(restored.last.message, 'started');
    expect(restored.first.createdAt, DateTime.utc(2026, 6, 13, 10, 30));
  });

  test('keeps ring capacity at 200', () {
    final store = _MemoryLocalKvStore();
    final repository = LogRepository(store: store);
    final entries = [
      for (var i = 0; i < 250; i++)
        LogEntry(
          id: '$i',
          level: LogLevel.info,
          message: 'm$i',
          createdAt: DateTime.utc(2026, 6, 13),
        ),
    ];

    repository.save(entries);
    expect(repository.load().length, 200);
  });

  test('falls back to empty list on malformed JSON', () {
    final store = _MemoryLocalKvStore();
    store.setString(StorageKeys.logRing, '{not valid json');
    final repository = LogRepository(store: store);

    expect(repository.load(), isEmpty);
  });

  test('restoreInto hydrates log signals', () {
    final store = _MemoryLocalKvStore();
    final repository = LogRepository(store: store);
    repository.save([
      LogEntry(
        id: '1',
        level: LogLevel.warning,
        message: 'persisted',
        createdAt: DateTime.utc(2026, 6, 13),
      ),
    ]);

    final logs = LogSignals();
    repository.restoreInto(logs);

    expect(logs.entries.value.single.message, 'persisted');
  });
}

class _MemoryLocalKvStore implements LocalKvStore {
  final Map<String, Object> _values = {};

  @override
  bool containsKey(String key) => _values.containsKey(key);

  @override
  bool getBool(String key, {bool defaultValue = false}) =>
      _values[key] as bool? ?? defaultValue;

  @override
  int getInt(String key, {int defaultValue = 0}) =>
      _values[key] as int? ?? defaultValue;

  @override
  String? getString(String key) => _values[key] as String?;

  @override
  void remove(String key) => _values.remove(key);

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
