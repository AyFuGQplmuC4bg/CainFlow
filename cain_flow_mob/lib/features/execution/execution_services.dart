import '../../core/network/provider_client.dart';
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
    this.downloaderOverride,
    this.statistics,
    this.executionSignals,
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

  /// Media downloader, defaulting to a real `dart:io` implementation.
  MediaDownloader get downloader => downloaderOverride ?? MediaDownloader();

  /// Workflow currently being executed, used for media asset attribution.
  final String workflowId;

  ExecutionServices copyWith({String? workflowId}) {
    return ExecutionServices(
      settingsRepository: settingsRepository,
      providerClient: providerClient,
      mediaRepository: mediaRepository,
      logs: logs,
      downloaderOverride: downloaderOverride,
      statistics: statistics,
      executionSignals: executionSignals,
      workflowId: workflowId ?? this.workflowId,
    );
  }
}
