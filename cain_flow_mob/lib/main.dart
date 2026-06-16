import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:mmkv/mmkv.dart';

import 'app/cain_flow_app.dart';
import 'core/storage/mmkv_local_kv_store.dart';
import 'features/background/background_execution_coordinator.dart';
import 'features/background/background_service_sync.dart';
import 'features/logs/log_repository.dart';
import 'features/logs/log_signals.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterForegroundTask.initCommunicationPort();
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'cain_flow_background_execution',
      channelName: 'CainFlow background execution',
      channelDescription:
          'Runs CainFlow workflows while the app is backgrounded.',
      onlyAlertOnce: true,
    ),
    iosNotificationOptions: const IOSNotificationOptions(
      showNotification: false,
      playSound: false,
    ),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.nothing(),
      autoRunOnBoot: false,
      autoRunOnMyPackageReplaced: false,
      allowWakeLock: true,
      allowWifiLock: true,
      allowAutoRestart: false,
      stopWithTask: false,
    ),
  );
  await MMKV.initialize(logLevel: MMKVLogLevel.Warning);
  final store = MmkvLocalKvStore();
  final logRepository = LogRepository(store: store);
  logRepository.restoreInto(logSignals);
  logSignals.onChanged = logRepository.save;
  initializeBackgroundExecutionCoordinator(store);
  initializeBackgroundServiceSync();
  runApp(const CainFlowApp());
}
