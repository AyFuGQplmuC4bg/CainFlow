import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'background_runner.dart';

const backgroundTaskReadyEventType = 'service_ready';

class BackgroundServiceEvent {
  const BackgroundServiceEvent({
    required this.type,
    this.jobId = '',
    this.message = '',
    this.progress = 0,
    this.payload = const {},
  });

  factory BackgroundServiceEvent.fromJson(Map<String, dynamic> json) {
    return BackgroundServiceEvent(
      type: json['type']?.toString() ?? '',
      jobId: json['jobId']?.toString() ?? '',
      message: json['message']?.toString() ?? '',
      progress: _doubleFrom(json['progress']),
      payload: json['payload'] is Map
          ? Map<String, dynamic>.from(json['payload'] as Map)
          : const {},
    );
  }

  final String type;
  final String jobId;
  final String message;
  final double progress;
  final Map<String, dynamic> payload;
}

class BackgroundTaskBridge {
  BackgroundTaskBridge();

  final StreamController<BackgroundServiceEvent> _events =
      StreamController<BackgroundServiceEvent>.broadcast();
  bool _callbackRegistered = false;
  final StreamController<void> _serviceReady =
      StreamController<void>.broadcast();
  bool _readyReceived = false;

  Future<void> startForegroundService({
    String jobId = '',
    Map<String, dynamic> workflow = const {},
  }) async {
    if (!_supportsAndroidForegroundService) return;
    _ensureCallbackRegistered();

    final isRunning = await FlutterForegroundTask.isRunningService;
    final result = isRunning
        ? FlutterForegroundTask.restartService()
        : FlutterForegroundTask.startService(
            serviceId: 1001,
            serviceTypes: const [ForegroundServiceTypes.dataSync],
            notificationTitle: 'CainFlow is running',
            notificationText: 'Background workflow execution is enabled.',
            callback: startCainFlowTaskCallback,
          );
    final resolvedResult = await result;

    if (resolvedResult case ServiceRequestFailure(:final error)) {
      throw error;
    }

    if (!isRunning) {
      _readyReceived = false;
      await _serviceReady.stream.first.timeout(const Duration(seconds: 5));
    }

    FlutterForegroundTask.sendDataToTask({
      'command': 'startWorkflow',
      if (jobId.isNotEmpty) 'jobId': jobId,
      if (workflow.isNotEmpty) 'workflow': workflow,
    });
  }

  Future<void> stopForegroundService({String jobId = ''}) async {
    if (!_supportsAndroidForegroundService) return;
    FlutterForegroundTask.sendDataToTask({
      'command': 'cancelWorkflow',
      if (jobId.isNotEmpty) 'jobId': jobId,
    });
    final result = await FlutterForegroundTask.stopService();
    if (result case ServiceRequestFailure(:final error)) {
      throw error;
    }
  }

  Stream<BackgroundServiceEvent> watchEvents() {
    _ensureCallbackRegistered();
    return _events.stream;
  }

  void _ensureCallbackRegistered() {
    if (_callbackRegistered || !_supportsAndroidForegroundService) return;
    _callbackRegistered = true;
    FlutterForegroundTask.addTaskDataCallback(_onReceiveTaskData);
  }

  void _onReceiveTaskData(Object data) {
    final event = _parseEvent(data);
    if (event.type == backgroundTaskReadyEventType && !_readyReceived) {
      _readyReceived = true;
      _serviceReady.add(null);
    }
    _events.add(event);
  }
}

BackgroundServiceEvent _parseEvent(dynamic event) {
  if (event is Map) {
    return BackgroundServiceEvent.fromJson(Map<String, dynamic>.from(event));
  }
  return BackgroundServiceEvent(type: event?.toString() ?? '');
}

double _doubleFrom(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

final backgroundTaskBridge = BackgroundTaskBridge();

bool get _supportsAndroidForegroundService =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
