import 'dart:convert';

import '../../core/models/workflow_document.dart';
import '../../core/storage/local_kv_store.dart';
import '../../core/storage/storage_keys.dart';

enum BackgroundJobStatus { queued, running, completed, failed, canceled }

class BackgroundAsyncTaskMetadata {
  const BackgroundAsyncTaskMetadata({
    required this.taskId,
    required this.provider,
    required this.pollUrl,
    required this.state,
    this.requestToken = '',
    this.nodeId = '',
    this.pollAttempts = 0,
    this.nextPollAt,
    this.deadlineAt,
    this.lastError,
  });

  factory BackgroundAsyncTaskMetadata.fromJson(Map<String, dynamic> json) {
    return BackgroundAsyncTaskMetadata(
      taskId: json['taskId']?.toString() ?? '',
      provider: json['provider']?.toString() ?? '',
      pollUrl: json['pollUrl']?.toString() ?? '',
      state: json['state']?.toString() ?? '',
      requestToken: json['requestToken']?.toString() ?? '',
      nodeId: json['nodeId']?.toString() ?? '',
      pollAttempts: _intFrom(json['pollAttempts']),
      nextPollAt: json['nextPollAt']?.toString(),
      deadlineAt: json['deadlineAt']?.toString(),
      lastError: json['lastError']?.toString(),
    );
  }

  final String taskId;
  final String provider;
  final String pollUrl;
  final String state;
  final String requestToken;
  final String nodeId;
  final int pollAttempts;
  final String? nextPollAt;
  final String? deadlineAt;
  final String? lastError;

  BackgroundAsyncTaskMetadata copyWith({
    String? taskId,
    String? provider,
    String? pollUrl,
    String? state,
    String? requestToken,
    String? nodeId,
    int? pollAttempts,
    String? nextPollAt,
    String? deadlineAt,
    String? lastError,
  }) {
    return BackgroundAsyncTaskMetadata(
      taskId: taskId ?? this.taskId,
      provider: provider ?? this.provider,
      pollUrl: pollUrl ?? this.pollUrl,
      state: state ?? this.state,
      requestToken: requestToken ?? this.requestToken,
      nodeId: nodeId ?? this.nodeId,
      pollAttempts: pollAttempts ?? this.pollAttempts,
      nextPollAt: nextPollAt ?? this.nextPollAt,
      deadlineAt: deadlineAt ?? this.deadlineAt,
      lastError: lastError ?? this.lastError,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'taskId': taskId,
      'provider': provider,
      'pollUrl': pollUrl,
      'state': state,
      if (requestToken.isNotEmpty) 'requestToken': requestToken,
      if (nodeId.isNotEmpty) 'nodeId': nodeId,
      if (pollAttempts > 0) 'pollAttempts': pollAttempts,
      if (nextPollAt != null) 'nextPollAt': nextPollAt,
      if (deadlineAt != null) 'deadlineAt': deadlineAt,
      if (lastError != null && lastError!.isNotEmpty) 'lastError': lastError,
    };
  }
}

typedef BackgroundAsyncTaskSnapshot = BackgroundAsyncTaskMetadata;

class BackgroundJobSnapshot {
  BackgroundJobSnapshot({
    required this.jobId,
    required this.workflow,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    BackgroundAsyncTaskMetadata? asyncTask,
    List<BackgroundAsyncTaskMetadata>? asyncTasks,
    this.error = '',
  }) : asyncTasks = asyncTasks ?? (asyncTask == null ? const [] : [asyncTask]),
       asyncTask = asyncTask ??
           ((asyncTasks != null && asyncTasks.isNotEmpty)
               ? asyncTasks.first
               : null);

  factory BackgroundJobSnapshot.fromJson(Map<String, dynamic> json) {
    final parsedTasks = _parseAsyncTasks(json);
    return BackgroundJobSnapshot(
      jobId: json['jobId']?.toString() ?? '',
      workflow: json['workflow'] is Map
          ? WorkflowDocument.fromJson(
              Map<String, dynamic>.from(json['workflow'] as Map),
            )
          : WorkflowDocument.empty(),
      status: _statusFrom(json['status']),
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      asyncTasks: parsedTasks,
      error: json['error']?.toString() ?? '',
    );
  }

  final String jobId;
  final WorkflowDocument workflow;
  final BackgroundJobStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final BackgroundAsyncTaskMetadata? asyncTask;
  final List<BackgroundAsyncTaskMetadata> asyncTasks;
  final String error;

  BackgroundJobSnapshot copyWith({
    WorkflowDocument? workflow,
    BackgroundJobStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    BackgroundAsyncTaskMetadata? asyncTask,
    List<BackgroundAsyncTaskMetadata>? asyncTasks,
    String? error,
    bool clearAsyncTask = false,
  }) {
    final nextTasks = clearAsyncTask
        ? const <BackgroundAsyncTaskMetadata>[]
        : asyncTasks ??
            (asyncTask != null
                ? <BackgroundAsyncTaskMetadata>[asyncTask]
                : this.asyncTasks);
    final nextTask = clearAsyncTask
        ? null
        : asyncTask ?? (nextTasks.isNotEmpty ? nextTasks.first : this.asyncTask);
    return BackgroundJobSnapshot(
      jobId: jobId,
      workflow: workflow ?? this.workflow,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      asyncTask: nextTask,
      asyncTasks: nextTasks,
      error: error ?? this.error,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'jobId': jobId,
      'workflow': workflow.toJson(),
      'status': status.name,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'updatedAt': updatedAt.toUtc().toIso8601String(),
      if (asyncTasks.isNotEmpty)
        'asyncTasks': asyncTasks.map((task) => task.toJson()).toList(),
      if (error.isNotEmpty) 'error': error,
    };
  }
}

class BackgroundJobRepository {
  const BackgroundJobRepository({required this.store});

  final LocalKvStore store;

  BackgroundJobSnapshot? loadJob(String jobId) {
    final raw = store.getString(StorageKeys.backgroundJob(jobId));
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final snapshot = BackgroundJobSnapshot.fromJson(
        Map<String, dynamic>.from(decoded),
      );
      return snapshot.jobId.isEmpty ? null : snapshot;
    } catch (_) {
      return null;
    }
  }

  BackgroundJobSnapshot? load(String jobId) => loadJob(jobId);

  List<BackgroundJobSnapshot> loadAll() {
    final ids = _loadIds();
    return [
      for (final id in ids)
        if (loadJob(id) case final snapshot?) snapshot,
    ];
  }

  List<BackgroundJobSnapshot> loadAllJobs() => loadAll();

  bool saveJob(BackgroundJobSnapshot snapshot) {
    if (snapshot.jobId.trim().isEmpty) return false;
    final saved = store.setString(
      StorageKeys.backgroundJob(snapshot.jobId),
      jsonEncode(snapshot.toJson()),
    );
    if (!saved) return false;

    final ids = _loadIds();
    if (!ids.contains(snapshot.jobId)) {
      ids.add(snapshot.jobId);
      return _saveIds(ids);
    }
    return true;
  }

  bool save(BackgroundJobSnapshot snapshot) => saveJob(snapshot);

  void remove(String jobId) {
    store.remove(StorageKeys.backgroundJob(jobId));
    final ids = _loadIds()..remove(jobId);
    _saveIds(ids);
  }

  List<String> _loadIds() {
    final raw = store.getString(StorageKeys.backgroundJobIndex);
    if (raw == null || raw.isEmpty) return <String>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <String>[];
      return decoded
          .map((item) => item.toString())
          .where((id) => id.isNotEmpty)
          .toList();
    } catch (_) {
      return <String>[];
    }
  }

  bool _saveIds(List<String> ids) {
    return store.setString(StorageKeys.backgroundJobIndex, jsonEncode(ids));
  }
}

List<BackgroundAsyncTaskMetadata> _parseAsyncTasks(Map<String, dynamic> json) {
  final list = json['asyncTasks'];
  if (list is List) {
    return list
        .whereType<Map>()
        .map((item) => BackgroundAsyncTaskMetadata.fromJson(
              Map<String, dynamic>.from(item),
            ))
        .where((task) => task.taskId.isNotEmpty)
        .toList();
  }
  final single = json['asyncTask'];
  if (single is Map) {
    final task = BackgroundAsyncTaskMetadata.fromJson(
      Map<String, dynamic>.from(single),
    );
    return task.taskId.isEmpty ? const [] : [task];
  }
  return const [];
}

int _intFrom(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

BackgroundJobStatus _statusFrom(Object? value) {
  return switch (value?.toString()) {
    'running' => BackgroundJobStatus.running,
    'completed' => BackgroundJobStatus.completed,
    'failed' => BackgroundJobStatus.failed,
    'canceled' => BackgroundJobStatus.canceled,
    _ => BackgroundJobStatus.queued,
  };
}
