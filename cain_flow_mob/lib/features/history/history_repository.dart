import 'dart:convert';

import '../../core/storage/local_kv_store.dart';
import '../../core/storage/storage_keys.dart';

/// A single execution-history entry: what ran and a thumbnail/result pointer.
class HistoryEntry {
  const HistoryEntry({
    required this.id,
    required this.workflowName,
    required this.createdAt,
    this.prompt = '',
    this.modelName = '',
    this.providerName = '',
    this.thumbnailRelativePath = '',
    this.resultRelativePath = '',
    this.resultUrl = '',
  });

  factory HistoryEntry.fromJson(Map<String, dynamic> json) {
    return HistoryEntry(
      id: json['id']?.toString() ?? '',
      workflowName: json['workflowName']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      prompt: json['prompt']?.toString() ?? '',
      modelName: json['modelName']?.toString() ?? '',
      providerName: json['providerName']?.toString() ?? '',
      thumbnailRelativePath: json['thumbnailRelativePath']?.toString() ?? '',
      resultRelativePath: json['resultRelativePath']?.toString() ?? '',
      resultUrl: json['resultUrl']?.toString() ?? '',
    );
  }

  final String id;
  final String workflowName;
  final DateTime createdAt;
  final String prompt;
  final String modelName;
  final String providerName;
  final String thumbnailRelativePath;
  final String resultRelativePath;
  final String resultUrl;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'workflowName': workflowName,
      'createdAt': createdAt.toUtc().toIso8601String(),
      if (prompt.isNotEmpty) 'prompt': prompt,
      if (modelName.isNotEmpty) 'modelName': modelName,
      if (providerName.isNotEmpty) 'providerName': providerName,
      if (thumbnailRelativePath.isNotEmpty)
        'thumbnailRelativePath': thumbnailRelativePath,
      if (resultRelativePath.isNotEmpty)
        'resultRelativePath': resultRelativePath,
      if (resultUrl.isNotEmpty) 'resultUrl': resultUrl,
    };
  }
}

/// Persists a bounded ring of execution-history entries in [LocalKvStore].
class HistoryRepository {
  HistoryRepository({required this.store, this.capacity = 100});

  final LocalKvStore store;
  final int capacity;

  List<HistoryEntry> loadAll() {
    final raw = store.getString(StorageKeys.historyRing);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((e) => HistoryEntry.fromJson(Map<String, dynamic>.from(e)))
          .where((e) => e.id.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Prepends [entry] (newest first), trimming to [capacity].
  void add(HistoryEntry entry) {
    final entries = [entry, ...loadAll()];
    if (entries.length > capacity) entries.removeRange(capacity, entries.length);
    _save(entries);
  }

  void remove(String id) {
    _save([for (final e in loadAll()) if (e.id != id) e]);
  }

  void clear() => store.remove(StorageKeys.historyRing);

  void _save(List<HistoryEntry> entries) {
    store.setString(
      StorageKeys.historyRing,
      jsonEncode(entries.map((e) => e.toJson()).toList()),
    );
  }
}
