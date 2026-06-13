import '../../core/network/provider_client.dart';
import '../logs/log_signals.dart';
import '../media/media_repository.dart';
import '../settings/provider_settings.dart';

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
  });

  final ProviderSettingsRepository settingsRepository;
  final ProviderClient providerClient;
  final MediaRepository mediaRepository;
  final LogSignals logs;

  /// Workflow currently being executed, used for media asset attribution.
  final String workflowId;

  ExecutionServices copyWith({String? workflowId}) {
    return ExecutionServices(
      settingsRepository: settingsRepository,
      providerClient: providerClient,
      mediaRepository: mediaRepository,
      logs: logs,
      workflowId: workflowId ?? this.workflowId,
    );
  }
}
