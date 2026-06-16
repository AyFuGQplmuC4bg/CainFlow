import 'dart:async';

import 'package:flutter/foundation.dart';

import '../execution/execution_signals.dart';
import '../logs/log_signals.dart';
import '../workbench/workbench_signals.dart';
import 'background_execution_coordinator.dart';
import 'background_service_channel.dart';

class BackgroundServiceSync {
  StreamSubscription<BackgroundServiceEvent>? _subscription;
  bool _initialized = false;

  void initialize() {
    if (_initialized || !_supportsAndroidForegroundService) return;
    _initialized = true;
    if (_subscription != null) return;
    _restoreActiveJob();
    _subscription = backgroundTaskBridge.watchEvents().listen(
      _handleEvent,
      onError: (Object error, StackTrace stackTrace) {
        logSignals.add(
          LogLevel.warning,
          'Background service event stream error: $error',
          scope: 'background_service',
        );
      },
    );
  }

  void _restoreActiveJob() {
    final active = defaultBackgroundExecutionCoordinator?.loadActiveJobs();
    if (active == null || active.isEmpty) return;
    final job = active.first;
    executionSignals.backgroundJobId.value = job.jobId;
    executionSignals.markWorkflowRunning();
    workbenchSignals.runState.value = WorkbenchRunState.running;
  }

  void _handleEvent(BackgroundServiceEvent event) {
    final coordinator = defaultBackgroundExecutionCoordinator;
    switch (event.type) {
      case backgroundTaskReadyEventType:
        if (event.message.isNotEmpty) {
          logSignals.add(
            LogLevel.info,
            event.message,
            scope: 'background_service',
          );
        }
        return;
      case 'started':
        executionSignals.backgroundJobId.value = event.jobId;
        executionSignals.markWorkflowRunning();
        workbenchSignals.runState.value = WorkbenchRunState.running;
        coordinator?.markRunning(event.jobId);
        logSignals.add(
          LogLevel.info,
          event.message.isEmpty
              ? 'Background workflow started: ${event.jobId}'
              : event.message,
          scope: 'background_service',
        );
        return;
      case 'completed':
        executionSignals.markWorkflowCompleted();
        executionSignals.backgroundJobId.value = '';
        workbenchSignals.runState.value = WorkbenchRunState.idle;
        coordinator?.markCompleted(event.jobId);
        logSignals.add(
          LogLevel.info,
          event.message.isEmpty
              ? 'Background workflow completed: ${event.jobId}'
              : event.message,
          scope: 'background_service',
        );
        return;
      case 'failed':
        executionSignals.markWorkflowFailed(
          event.message.isEmpty ? 'Background workflow failed' : event.message,
        );
        executionSignals.backgroundJobId.value = '';
        workbenchSignals.runState.value = WorkbenchRunState.idle;
        coordinator?.markFailed(
          event.jobId,
          error: event.message.isEmpty
              ? 'Background workflow failed'
              : event.message,
        );
        logSignals.add(
          LogLevel.error,
          event.message.isEmpty
              ? 'Background workflow failed: ${event.jobId}'
              : event.message,
          scope: 'background_service',
        );
        return;
      case 'canceled':
        executionSignals.markWorkflowCanceled();
        executionSignals.backgroundJobId.value = '';
        workbenchSignals.runState.value = WorkbenchRunState.stopped;
        coordinator?.markCanceled(event.jobId);
        logSignals.add(
          LogLevel.warning,
          event.message.isEmpty
              ? 'Background workflow canceled: ${event.jobId}'
              : event.message,
          scope: 'background_service',
        );
        return;
      case 'node_running':
        if (event.payload['nodeId'] case final String nodeId
            when nodeId.isNotEmpty) {
          executionSignals.markNode(nodeId, NodeRunState.running);
        }
        return;
      case 'node_completed':
        if (event.payload['nodeId'] case final String nodeId
            when nodeId.isNotEmpty) {
          executionSignals.markNode(
            nodeId,
            NodeRunState.completed,
            message: event.message,
          );
        }
        return;
      case 'node_failed':
        if (event.payload['nodeId'] case final String nodeId
            when nodeId.isNotEmpty) {
          executionSignals.markNode(
            nodeId,
            NodeRunState.failed,
            message: event.message,
          );
        }
        return;
      case 'node_skipped':
        if (event.payload['nodeId'] case final String nodeId
            when nodeId.isNotEmpty) {
          executionSignals.markNode(
            nodeId,
            NodeRunState.skipped,
            message: event.message,
          );
        }
        return;
      case 'poll_progress':
        if (event.payload['nodeId'] case final String nodeId
            when nodeId.isNotEmpty) {
          executionSignals.setPollProgress(nodeId, event.message);
        }
        return;
      case 'image_output':
        if (event.payload['nodeId'] case final String nodeId
            when nodeId.isNotEmpty) {
          final image = Map<String, dynamic>.from(event.payload)
            ..remove('nodeId');
          if (image.isNotEmpty) {
            executionSignals.setImageOutput(nodeId, image);
          }
        }
        return;
      default:
        if (event.message.isNotEmpty) {
          logSignals.add(
            LogLevel.info,
            event.message,
            scope: 'background_service',
          );
        }
        return;
    }
  }
}

bool get _supportsAndroidForegroundService =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

final backgroundServiceSync = BackgroundServiceSync();

void initializeBackgroundServiceSync() {
  backgroundServiceSync.initialize();
}
