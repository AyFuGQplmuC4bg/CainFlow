import '../../core/models/workflow_document.dart';
import '../../core/storage/local_kv_store.dart';
import 'background_job_repository.dart';

class BackgroundExecutionCoordinator {
  BackgroundExecutionCoordinator({
    required this.repository,
    DateTime Function()? now,
    String Function()? jobIdGenerator,
  }) : _now = now ?? DateTime.now,
       _jobIdGenerator = jobIdGenerator ?? _defaultJobIdGenerator;

  final BackgroundJobRepository repository;
  final DateTime Function() _now;
  final String Function() _jobIdGenerator;

  BackgroundJobSnapshot enqueueWorkflow({
    required WorkflowDocument workflow,
    BackgroundAsyncTaskMetadata? asyncTask,
    String? jobId,
  }) {
    final timestamp = _timestamp();
    final snapshot = BackgroundJobSnapshot(
      jobId: jobId ?? _jobIdGenerator(),
      workflow: workflow,
      status: BackgroundJobStatus.queued,
      createdAt: timestamp,
      updatedAt: timestamp,
      asyncTask: asyncTask,
      asyncTasks: asyncTask == null ? const [] : [asyncTask],
    );
    repository.saveJob(snapshot);
    return snapshot;
  }

  BackgroundJobSnapshot createQueuedJob({
    required String jobId,
    required WorkflowDocument workflow,
    DateTime Function()? now,
  }) {
    final timestamp = (now ?? _now)().toUtc();
    final snapshot = BackgroundJobSnapshot(
      jobId: jobId,
      workflow: workflow,
      status: BackgroundJobStatus.queued,
      createdAt: timestamp,
      updatedAt: timestamp,
    );
    repository.saveJob(snapshot);
    return snapshot;
  }

  BackgroundJobSnapshot? markRunning(
    String jobId, {
    BackgroundAsyncTaskMetadata? asyncTask,
  }) {
    return _update(
      jobId,
      status: BackgroundJobStatus.running,
      asyncTask: asyncTask,
    );
  }

  BackgroundJobSnapshot? markCompleted(String jobId) {
    return _update(jobId, status: BackgroundJobStatus.completed);
  }

  BackgroundJobSnapshot? markFailed(
    String jobId, {
    required String error,
  }) {
    return _update(
      jobId,
      status: BackgroundJobStatus.failed,
      error: error,
    );
  }

  BackgroundJobSnapshot? markCanceled(String jobId) {
    return _update(jobId, status: BackgroundJobStatus.canceled);
  }

  BackgroundJobSnapshot? saveAsyncTask(
    String jobId,
    BackgroundAsyncTaskMetadata asyncTask,
  ) {
    final existing = repository.loadJob(jobId);
    if (existing == null) return null;
    final tasks = _mergeAsyncTasks(existing.asyncTasks, asyncTask);
    final updated = existing.copyWith(
      updatedAt: _timestamp(),
      asyncTask: asyncTask,
      asyncTasks: tasks,
    );
    repository.saveJob(updated);
    return updated;
  }

  BackgroundJobSnapshot? upsertAsyncTask(
    String jobId,
    BackgroundAsyncTaskSnapshot task, {
    DateTime Function()? now,
  }) {
    final existing = repository.loadJob(jobId);
    if (existing == null) return null;
    final updated = existing.copyWith(
      updatedAt: (now ?? _now)().toUtc(),
      asyncTask: task,
      asyncTasks: _mergeAsyncTasks(existing.asyncTasks, task),
    );
    repository.saveJob(updated);
    return updated;
  }

  BackgroundJobSnapshot? loadJob(String jobId) => repository.loadJob(jobId);

  BackgroundJobSnapshot? load(String jobId) => loadJob(jobId);

  List<BackgroundJobSnapshot> loadRestorableJobs() {
    return repository.loadAllJobs().where((snapshot) {
      return snapshot.status == BackgroundJobStatus.queued ||
          snapshot.status == BackgroundJobStatus.running;
    }).toList();
  }

  List<BackgroundJobSnapshot> loadActiveJobs() => loadRestorableJobs();

  BackgroundJobSnapshot? _update(
    String jobId, {
    required BackgroundJobStatus status,
    BackgroundAsyncTaskMetadata? asyncTask,
    String? error,
  }) {
    final existing = repository.loadJob(jobId);
    if (existing == null) return null;
    final nextAsyncTask = asyncTask ?? existing.asyncTask;
    final updated = existing.copyWith(
      status: status,
      updatedAt: _timestamp(),
      asyncTask: nextAsyncTask,
      asyncTasks: nextAsyncTask == null
          ? existing.asyncTasks
          : _mergeAsyncTasks(existing.asyncTasks, nextAsyncTask),
      error: error ?? existing.error,
    );
    repository.saveJob(updated);
    return updated;
  }

  List<BackgroundAsyncTaskMetadata> _mergeAsyncTasks(
    List<BackgroundAsyncTaskMetadata> current,
    BackgroundAsyncTaskMetadata next,
  ) {
    final matchedByNode = next.nodeId.isNotEmpty;
    final filtered = [
      for (final candidate in current)
        if (candidate.taskId != next.taskId &&
            (!matchedByNode || candidate.nodeId != next.nodeId))
          candidate,
    ];
    return [next, ...filtered];
  }

  DateTime _timestamp() => _now().toUtc();

  static String _defaultJobIdGenerator() {
    return 'bg_${DateTime.now().microsecondsSinceEpoch}';
  }
}

BackgroundExecutionCoordinator? _defaultBackgroundExecutionCoordinator;

void initializeBackgroundExecutionCoordinator(LocalKvStore store) {
  _defaultBackgroundExecutionCoordinator = BackgroundExecutionCoordinator(
    repository: BackgroundJobRepository(store: store),
  );
}

BackgroundExecutionCoordinator? get defaultBackgroundExecutionCoordinator =>
    _defaultBackgroundExecutionCoordinator;
