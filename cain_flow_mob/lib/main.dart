import 'package:flutter/material.dart';
import 'package:mmkv/mmkv.dart';

import 'app/cain_flow_app.dart';
import 'core/storage/mmkv_local_kv_store.dart';
import 'features/background/background_execution_coordinator.dart';
import 'features/logs/log_repository.dart';
import 'features/logs/log_signals.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await MMKV.initialize(logLevel: MMKVLogLevel.Warning);
  final store = MmkvLocalKvStore();
  final logRepository = LogRepository(store: store);
  logRepository.restoreInto(logSignals);
  logSignals.onChanged = logRepository.save;
  initializeBackgroundExecutionCoordinator(store);
  runApp(const CainFlowApp());
}
