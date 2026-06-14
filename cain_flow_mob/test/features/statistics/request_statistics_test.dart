import 'package:cain_flow_mob/core/storage/local_kv_store.dart';
import 'package:cain_flow_mob/features/statistics/request_statistics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('records totals and per-model breakdown for a day', () {
    var now = DateTime.utc(2026, 6, 1, 10);
    final stats = RequestStatistics(store: _MemStore(), now: () => now);

    stats.record(provider: 'p1', model: 'gpt-4.1');
    stats.record(provider: 'p1', model: 'gpt-4.1');
    stats.record(provider: 'p2', model: 'gemini', success: false);

    expect(stats.totalRequests(), 3);
    expect(stats.modelTotals()['gpt-4.1'], 2);
    expect(stats.modelTotals()['gemini'], 1);
  });

  test('separates counts by day and reports daily totals sorted', () {
    var now = DateTime.utc(2026, 6, 1, 10);
    final stats = RequestStatistics(store: _MemStore(), now: () => now);
    stats.record(provider: 'p', model: 'm');
    now = DateTime.utc(2026, 6, 2, 10);
    stats.record(provider: 'p', model: 'm');
    stats.record(provider: 'p', model: 'm');

    final daily = stats.dailyTotals();
    expect(daily['2026-06-01'], 1);
    expect(daily['2026-06-02'], 2);
    expect(daily.keys.toList(), ['2026-06-01', '2026-06-02']);
  });

  test('trims to retention window', () {
    var day = DateTime.utc(2026, 6, 1, 10);
    final stats = RequestStatistics(
      store: _MemStore(),
      retentionDays: 3,
      now: () => day,
    );
    for (var i = 0; i < 5; i++) {
      day = DateTime.utc(2026, 6, 1 + i, 10);
      stats.record(provider: 'p', model: 'm');
    }
    expect(stats.dailyTotals().length, 3);
    // Oldest two days dropped.
    expect(stats.dailyTotals().containsKey('2026-06-01'), isFalse);
    expect(stats.dailyTotals().containsKey('2026-06-05'), isTrue);
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
