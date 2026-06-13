import 'dart:convert';

import '../../core/storage/local_kv_store.dart';
import '../../core/storage/storage_keys.dart';
import 'log_signals.dart';

/// Persists the in-memory log ring to [LocalKvStore] under
/// [StorageKeys.logRing]. Entries are already sanitized before they reach the
/// log signals, so this is a straight JSON round-trip.
class LogRepository {
  const LogRepository({required this.store, this.capacity = 200});

  final LocalKvStore store;
  final int capacity;

  List<LogEntry> load() {
    final raw = store.getString(StorageKeys.logRing);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((item) => LogEntry.fromJson(Map<String, dynamic>.from(item)))
          .where((entry) => entry.id.isNotEmpty)
          .take(capacity)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  bool save(List<LogEntry> entries) {
    final limited = entries.take(capacity).toList();
    return store.setString(
      StorageKeys.logRing,
      jsonEncode(limited.map((entry) => entry.toJson()).toList()),
    );
  }

  /// Hydrates [logs] from storage on startup.
  void restoreInto(LogSignals logs) {
    final loaded = load();
    if (loaded.isNotEmpty) logs.replaceAll(loaded);
  }
}
