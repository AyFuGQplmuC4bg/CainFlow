import 'dart:convert';

import '../../core/storage/local_kv_store.dart';
import '../../core/storage/storage_keys.dart';

/// A saved prompt template.
class PromptTemplate {
  const PromptTemplate({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
  });

  factory PromptTemplate.fromJson(Map<String, dynamic> json) {
    return PromptTemplate(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      body: json['body']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  final String id;
  final String title;
  final String body;
  final DateTime createdAt;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'body': body,
      'createdAt': createdAt.toUtc().toIso8601String(),
    };
  }
}

/// CRUD store for prompt templates persisted in [LocalKvStore].
class PromptLibrary {
  PromptLibrary({required this.store});

  final LocalKvStore store;
  int _seq = 0;

  List<PromptTemplate> loadAll() {
    final raw = store.getString(StorageKeys.promptLibrary);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((e) => PromptTemplate.fromJson(Map<String, dynamic>.from(e)))
          .where((e) => e.id.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Adds a new template and returns it.
  PromptTemplate add(String title, String body) {
    final template = PromptTemplate(
      id: 'pt_${DateTime.now().microsecondsSinceEpoch}_${_seq++}',
      title: title.trim().isEmpty ? 'Untitled' : title.trim(),
      body: body,
      createdAt: DateTime.now().toUtc(),
    );
    _save([template, ...loadAll()]);
    return template;
  }

  void update(String id, {String? title, String? body}) {
    _save([
      for (final t in loadAll())
        if (t.id == id)
          PromptTemplate(
            id: t.id,
            title: title ?? t.title,
            body: body ?? t.body,
            createdAt: t.createdAt,
          )
        else
          t,
    ]);
  }

  void remove(String id) {
    _save([for (final t in loadAll()) if (t.id != id) t]);
  }

  void _save(List<PromptTemplate> templates) {
    store.setString(
      StorageKeys.promptLibrary,
      jsonEncode(templates.map((t) => t.toJson()).toList()),
    );
  }
}
