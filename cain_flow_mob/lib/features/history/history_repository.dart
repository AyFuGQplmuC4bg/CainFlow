import 'dart:convert';

import '../../core/storage/local_kv_store.dart';
import '../../core/storage/storage_keys.dart';

/// A single execution-history entry: what ran and a thumbnail/result pointer.
class HistoryEntry {
  const HistoryEntry({
    required this.id,
    required this.workflowName,
    required this.createdAt,
    this.durationMillis = 0,
    this.stage,
    this.outputs = const [],
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
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      durationMillis: _intFrom(json['durationMillis']),
      stage: json['stage'] is Map
          ? StageSummary.fromJson(
              Map<String, dynamic>.from(json['stage'] as Map),
            )
          : null,
      outputs: _outputsFromJson(json),
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
  final int durationMillis;
  final StageSummary? stage;
  final List<RunOutput> outputs;
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
      if (durationMillis > 0) 'durationMillis': durationMillis,
      if (stage != null) 'stage': stage!.toJson(),
      if (outputs.isNotEmpty)
        'outputs': outputs.map((output) => output.toJson()).toList(),
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

enum RunOutputKind {
  image,
  text;

  static RunOutputKind fromJson(Object? value) {
    return switch (value?.toString()) {
      'image' => RunOutputKind.image,
      'text' => RunOutputKind.text,
      _ => RunOutputKind.text,
    };
  }
}

class StageSummary {
  const StageSummary({
    required this.label,
    required this.kind,
    this.nodeCount = 0,
    this.keyNodeTitles = const [],
  });

  factory StageSummary.fromJson(Map<String, dynamic> json) {
    return StageSummary(
      label: json['label']?.toString() ?? '',
      kind: json['kind']?.toString() ?? '',
      nodeCount: _intFrom(json['nodeCount']),
      keyNodeTitles: json['keyNodeTitles'] is List
          ? [
              for (final title in json['keyNodeTitles'] as List)
                title.toString(),
            ]
          : const [],
    );
  }

  final String label;
  final String kind;
  final int nodeCount;
  final List<String> keyNodeTitles;

  Map<String, dynamic> toJson() {
    return {
      'label': label,
      'kind': kind,
      if (nodeCount > 0) 'nodeCount': nodeCount,
      if (keyNodeTitles.isNotEmpty) 'keyNodeTitles': keyNodeTitles,
    };
  }
}

class RunOutput {
  const RunOutput({
    required this.id,
    required this.kind,
    required this.nodeId,
    this.nodeTitle = '',
    this.text = '',
    this.relativePath = '',
    this.thumbnailRelativePath = '',
    this.url = '',
    this.mimeType = '',
  });

  factory RunOutput.fromJson(Map<String, dynamic> json) {
    return RunOutput(
      id: json['id']?.toString() ?? '',
      kind: RunOutputKind.fromJson(json['kind']),
      nodeId: json['nodeId']?.toString() ?? '',
      nodeTitle: json['nodeTitle']?.toString() ?? '',
      text: json['text']?.toString() ?? '',
      relativePath: json['relativePath']?.toString() ?? '',
      thumbnailRelativePath: json['thumbnailRelativePath']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      mimeType: json['mimeType']?.toString() ?? '',
    );
  }

  final String id;
  final RunOutputKind kind;
  final String nodeId;
  final String nodeTitle;
  final String text;
  final String relativePath;
  final String thumbnailRelativePath;
  final String url;
  final String mimeType;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'kind': kind.name,
      'nodeId': nodeId,
      if (nodeTitle.isNotEmpty) 'nodeTitle': nodeTitle,
      if (text.isNotEmpty) 'text': text,
      if (relativePath.isNotEmpty) 'relativePath': relativePath,
      if (thumbnailRelativePath.isNotEmpty)
        'thumbnailRelativePath': thumbnailRelativePath,
      if (url.isNotEmpty) 'url': url,
      if (mimeType.isNotEmpty) 'mimeType': mimeType,
    };
  }

  Map<String, dynamic> toImagePayload() {
    if (url.isNotEmpty) {
      return {'kind': 'url', 'url': url};
    }
    return {
      'kind': 'asset',
      if (relativePath.isNotEmpty) 'relativePath': relativePath,
      if (thumbnailRelativePath.isNotEmpty)
        'thumbnailRelativePath': thumbnailRelativePath,
      if (mimeType.isNotEmpty) 'mimeType': mimeType,
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
    if (raw == null || raw.isEmpty) {
      return const [];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return const [];
      }
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
    if (entries.length > capacity) {
      entries.removeRange(capacity, entries.length);
    }
    _save(entries);
  }

  void remove(String id) {
    final kept = <HistoryEntry>[];
    for (final entry in loadAll()) {
      if (entry.id != id) {
        kept.add(entry);
      }
    }
    _save(kept);
  }

  void clear() => store.remove(StorageKeys.historyRing);

  void _save(List<HistoryEntry> entries) {
    store.setString(
      StorageKeys.historyRing,
      jsonEncode(entries.map((e) => e.toJson()).toList()),
    );
  }
}

List<RunOutput> _outputsFromJson(Map<String, dynamic> json) {
  final outputs = json['outputs'];
  if (outputs is List) {
    return outputs
        .whereType<Map>()
        .map((item) => RunOutput.fromJson(Map<String, dynamic>.from(item)))
        .where((output) => output.id.isNotEmpty)
        .toList();
  }

  final resultUrl = json['resultUrl']?.toString() ?? '';
  final resultRelativePath = json['resultRelativePath']?.toString() ?? '';
  final thumbnailRelativePath = json['thumbnailRelativePath']?.toString() ?? '';
  if (resultUrl.isEmpty &&
      resultRelativePath.isEmpty &&
      thumbnailRelativePath.isEmpty) {
    return const [];
  }
  return [
    RunOutput(
      id: '${json['id'] ?? 'legacy'}_image',
      kind: RunOutputKind.image,
      nodeId: '',
      relativePath: resultRelativePath,
      thumbnailRelativePath: thumbnailRelativePath,
      url: resultUrl,
    ),
  ];
}

int _intFrom(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value?.toString() ?? '') ?? 0;
}
