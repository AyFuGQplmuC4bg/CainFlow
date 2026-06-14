import 'dart:convert';

import '../../core/storage/local_kv_store.dart';
import '../../core/storage/storage_keys.dart';

/// Aggregated request counts keyed by day, with per-provider and per-model
/// breakdowns. Retains a bounded number of recent days.
class RequestStatistics {
  RequestStatistics({
    required this.store,
    this.retentionDays = 7,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final LocalKvStore store;
  final int retentionDays;
  final DateTime Function() _now;

  /// Records one request against today's bucket.
  void record({
    required String provider,
    required String model,
    bool success = true,
  }) {
    final data = _load();
    final day = _dayKey(_now());
    final dayMap = Map<String, dynamic>.from(data[day] as Map? ?? {});

    dayMap['total'] = (dayMap['total'] as int? ?? 0) + 1;
    if (!success) dayMap['failed'] = (dayMap['failed'] as int? ?? 0) + 1;

    final providers = Map<String, dynamic>.from(dayMap['providers'] as Map? ?? {});
    if (provider.isNotEmpty) {
      providers[provider] = (providers[provider] as int? ?? 0) + 1;
    }
    dayMap['providers'] = providers;

    final models = Map<String, dynamic>.from(dayMap['models'] as Map? ?? {});
    if (model.isNotEmpty) {
      models[model] = (models[model] as int? ?? 0) + 1;
    }
    dayMap['models'] = models;

    data[day] = dayMap;
    _trim(data);
    _save(data);
  }

  /// Total requests across all retained days.
  int totalRequests() {
    var sum = 0;
    for (final day in _load().values) {
      if (day is Map) sum += (day['total'] as int? ?? 0);
    }
    return sum;
  }

  /// Per-day totals, newest day key last (sorted ascending).
  Map<String, int> dailyTotals() {
    final data = _load();
    final keys = data.keys.toList()..sort();
    return {
      for (final k in keys) k: (data[k] as Map?)?['total'] as int? ?? 0,
    };
  }

  /// Aggregated counts per model across retained days.
  Map<String, int> modelTotals() {
    final totals = <String, int>{};
    for (final day in _load().values) {
      if (day is! Map) continue;
      final models = day['models'];
      if (models is Map) {
        models.forEach((k, v) {
          totals[k.toString()] = (totals[k.toString()] ?? 0) + (v as int? ?? 0);
        });
      }
    }
    return totals;
  }

  void clear() => store.remove(StorageKeys.requestStats);

  Map<String, dynamic> _load() {
    final raw = store.getString(StorageKeys.requestStats);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : {};
    } catch (_) {
      return {};
    }
  }

  void _save(Map<String, dynamic> data) {
    store.setString(StorageKeys.requestStats, jsonEncode(data));
  }

  void _trim(Map<String, dynamic> data) {
    if (data.length <= retentionDays) return;
    final keys = data.keys.toList()..sort();
    final remove = keys.take(data.length - retentionDays);
    for (final k in remove) {
      data.remove(k);
    }
  }

  String _dayKey(DateTime t) {
    final u = t.toUtc();
    return '${u.year.toString().padLeft(4, '0')}-'
        '${u.month.toString().padLeft(2, '0')}-'
        '${u.day.toString().padLeft(2, '0')}';
  }
}
