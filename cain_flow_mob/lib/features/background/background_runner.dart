import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:mmkv/mmkv.dart';

import '../../core/models/workflow_document.dart';
import '../../core/network/provider_client.dart';
import '../../core/network/retrying_provider_client.dart';
import '../../core/storage/mmkv_local_kv_store.dart';
import '../execution/cain_flow_node_executor.dart';
import '../execution/execution_services.dart';
import '../execution/execution_signals.dart';
import '../history/history_repository.dart';
import '../logs/log_repository.dart';
import '../logs/log_signals.dart';
import '../media/media_repository.dart';
import '../settings/provider_settings.dart';
import '../statistics/request_statistics.dart';
import '../workbench/completion_feedback.dart';
import '../workbench/workbench_execution_controller.dart';
import '../workbench/workbench_signals.dart';
import '../workbench/workbench_workflow_mapper.dart';
import 'background_execution_coordinator.dart';
import 'background_service_channel.dart';

@pragma('vm:entry-point')
void startCainFlowTaskCallback() {
  FlutterForegroundTask.setTaskHandler(CainFlowTaskHandler());
}

class CainFlowTaskHandler extends TaskHandler {
  WorkbenchExecutionController? _controller;
  ExecutionSignals? _executionSignals;
  String _activeJobId = '';
  bool _isReady = false;
  Map<String, dynamic>? _pendingStartCommand;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    WidgetsFlutterBinding.ensureInitialized();
    await MMKV.initialize(logLevel: MMKVLogLevel.Warning);
    final store = MmkvLocalKvStore();
    final settingsRepository = ProviderSettingsRepository(store: store);
    final logRepository = LogRepository(store: store);
    logRepository.restoreInto(logSignals);
    logSignals.onChanged = logRepository.save;
    initializeBackgroundExecutionCoordinator(store);
    final runtime = settingsRepository.load().runtime;

    final providerClient = RetryingProviderClient(
      inner: DartIoProviderClient(),
      maxRetries: runtime.retryCount,
    );
    final executionSignals = ExecutionSignals(onEvent: _emitBackgroundEvent);
    final services = ExecutionServices(
      settingsRepository: settingsRepository,
      providerClient: providerClient,
      mediaRepository: MediaRepository(store: store),
      logs: logSignals,
      statistics: RequestStatistics(store: store),
      executionSignals: executionSignals,
      backgroundCoordinator: defaultBackgroundExecutionCoordinator,
    );
    _executionSignals = executionSignals;
    _controller = WorkbenchExecutionController(
      workbench: workbenchSignals,
      executor: CainFlowNodeExecutor(services: services),
      executionSignals: executionSignals,
      logs: logSignals,
      maxConcurrency: runtime.maxConcurrency,
      historyRepository: HistoryRepository(store: store),
      feedback: CompletionFeedback(soundEnabled: false, hapticsEnabled: false),
      backgroundCoordinator: defaultBackgroundExecutionCoordinator,
    );
    _isReady = true;
    _emitBackgroundEvent({
      'type': backgroundTaskReadyEventType,
      'message': 'Foreground task ready',
      'payload': {'starter': starter.name},
    });
    final pendingStart = _pendingStartCommand;
    if (pendingStart != null) {
      _pendingStartCommand = null;
      onReceiveData(pendingStart);
    }
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    final jobId = _activeJobId;
    if (isTimeout && jobId.isNotEmpty) {
      defaultBackgroundExecutionCoordinator?.markFailed(
        jobId,
        error: 'Foreground task timed out',
      );
      _emitBackgroundEvent({
        'type': 'failed',
        'jobId': jobId,
        'message': 'Foreground task timed out',
      });
    }
    _isReady = false;
    _pendingStartCommand = null;
    _activeJobId = '';
    _executionSignals?.backgroundJobId.value = '';
  }

  @override
  void onReceiveData(Object data) {
    if (data is! Map) return;
    final args = Map<String, dynamic>.from(data);
    switch (args['command']?.toString()) {
      case 'startWorkflow':
        if (!_isReady) {
          _pendingStartCommand = args;
          return;
        }
        final jobId = args['jobId']?.toString() ?? '';
        final workflow = args['workflow'] is Map
            ? WorkflowDocument.fromJson(
                Map<String, dynamic>.from(args['workflow'] as Map),
              )
            : WorkflowDocument.empty();
        unawaited(_handleStartWorkflow(jobId, workflow));
        return;
      case 'cancelWorkflow':
        _controller?.stop();
        return;
      default:
        return;
    }
  }

  Future<void> _handleStartWorkflow(
    String jobId,
    WorkflowDocument workflow,
  ) async {
    final controller = _controller;
    final executionSignals = _executionSignals;
    if (controller == null || executionSignals == null) return;
    _activeJobId = jobId;
    try {
      executionSignals.backgroundJobId.value = jobId;
      applyWorkflowToWorkbench(workbenchSignals, workflow, name: workflow.name);
      await controller.run(workflow: workflow, jobId: jobId);
    } catch (error) {
      _emitBackgroundEvent({
        'type': 'failed',
        'jobId': jobId,
        'message': error.toString(),
      });
      rethrow;
    } finally {
      final terminalState = executionSignals.workflowState.value;
      _activeJobId = '';
      executionSignals.backgroundJobId.value = '';
      if (terminalState == WorkflowExecutionState.completed ||
          terminalState == WorkflowExecutionState.failed ||
          terminalState == WorkflowExecutionState.canceled) {
        await FlutterForegroundTask.stopService();
      }
    }
  }

  void _emitBackgroundEvent(Map<String, dynamic> event) {
    FlutterForegroundTask.sendDataToMain(event);
  }
}
