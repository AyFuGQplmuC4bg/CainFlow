import '../../core/network/provider_client.dart';
import '../background/background_execution_coordinator.dart';
import '../background/background_job_repository.dart';
import '../logs/log_signals.dart';
import '../media/media_downloader.dart';
import '../media/media_repository.dart';
import '../settings/provider_settings.dart';
import '../statistics/request_statistics.dart';
import 'execution_signals.dart';

/// Bundle of runtime collaborators a concrete node executor needs.
///
/// The [WorkflowRunner] stays orchestration-only and never references these;
/// only the concrete executor receives them.
class ExecutionServices {
  const ExecutionServices({
    required this.settingsRepository,
    required this.providerClient,
    required this.mediaRepository,
    required this.logs,
    this.workflowId = '',
    this.backgroundJobId = '',
    this.downloaderOverride,
    this.statistics,
    this.executionSignals,
    this.backgroundCoordinator,
  });

  final ProviderSettingsRepository settingsRepository;
  final ProviderClient providerClient;
  final MediaRepository mediaRepository;
  final LogSignals logs;

  /// Optional injected downloader (tests); production resolves a real one.
  final MediaDownloader? downloaderOverride;

  /// Optional request statistics sink.
  final RequestStatistics? statistics;

  /// Optional execution signals, so nodes can publish transient progress
  /// (e.g. async polling text). Null in unit tests that don't assert progress.
  final ExecutionSignals? executionSignals;

  /// Optional background persistence hook for resumable async tasks.
  final BackgroundExecutionCoordinator? backgroundCoordinator;

  /// Active background job id when this execution participates in a
  /// restorable plugin-backed background run.
  final String backgroundJobId;

  String get activeBackgroundJobId {
    final explicit = backgroundJobId.trim();
    if (explicit.isNotEmpty) return explicit;
    return executionSignals?.backgroundJobId.value.trim() ?? '';
  }

  /// Media downloader, defaulting to a real `dart:io` implementation.
  MediaDownloader get downloader => downloaderOverride ?? MediaDownloader();

  /// Workflow currently being executed, used for media asset attribution.
  final String workflowId;

  BackgroundAsyncTaskMetadata? loadAsyncTaskForNode(String nodeId) {
    final jobId = activeBackgroundJobId;
    if (jobId.isEmpty) return null;
    final snapshot = backgroundCoordinator?.loadJob(jobId);
    if (snapshot == null) return null;
    for (final task in snapshot.asyncTasks) {
      if (task.nodeId == nodeId) return task;
    }
    return null;
  }

  ExecutionServices copyWith({String? workflowId, String? backgroundJobId}) {
    return ExecutionServices(
      settingsRepository: settingsRepository,
      providerClient: providerClient,
      mediaRepository: mediaRepository,
      logs: logs,
      downloaderOverride: downloaderOverride,
      statistics: statistics,
      executionSignals: executionSignals,
      backgroundCoordinator: backgroundCoordinator,
      workflowId: workflowId ?? this.workflowId,
      backgroundJobId: backgroundJobId ?? this.backgroundJobId,
    );
  }
}
