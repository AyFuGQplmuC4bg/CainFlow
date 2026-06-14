import 'dart:convert';

import '../../core/models/workflow_document.dart';
import '../../core/storage/local_kv_store.dart';
import '../../core/storage/storage_keys.dart';

class WorkflowRepository {
  WorkflowRepository({required this.store});

  final LocalKvStore store;

  List<String> listWorkflowIds() {
    final raw = store.getString(StorageKeys.workflowIndex);
    if (raw == null || raw.isEmpty) return const [];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded.map((item) => item.toString()).where((id) => id.isNotEmpty).toList();
    } catch (_) {
      return const [];
    }
  }

  WorkflowDocument? loadWorkflow(String id) {
    final raw = store.getString(StorageKeys.workflowDocument(id));
    if (raw == null || raw.isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return WorkflowDocument.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return null;
    }
  }

  bool saveWorkflow(String id, WorkflowDocument document) {
    if (id.trim().isEmpty) return false;

    final saved = store.setString(
      StorageKeys.workflowDocument(id),
      jsonEncode(document.toJson()),
    );
    if (!saved) return false;

    final ids = List<String>.from(listWorkflowIds());
    if (!ids.contains(id)) {
      ids.add(id);
      return store.setString(StorageKeys.workflowIndex, jsonEncode(ids));
    }
    return true;
  }

  void deleteWorkflow(String id) {
    store.remove(StorageKeys.workflowDocument(id));
    final ids = listWorkflowIds()..remove(id);
    store.setString(StorageKeys.workflowIndex, jsonEncode(ids));
  }

  /// Persists the id of the last active workflow so it can be restored on
  /// next app launch.
  void saveActiveId(String id) {
    store.setString(StorageKeys.activeWorkflowId, id);
  }

  /// Returns the id that was last marked active, or null if none.
  String? loadActiveId() {
    final raw = store.getString(StorageKeys.activeWorkflowId);
    return (raw == null || raw.isEmpty) ? null : raw;
  }

  void clearActiveId() {
    store.remove(StorageKeys.activeWorkflowId);
  }
}
