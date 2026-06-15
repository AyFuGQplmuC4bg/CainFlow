import 'package:flutter/material.dart';
import 'package:mmkv/mmkv.dart';

import 'app/cain_flow_app.dart';
import 'core/storage/mmkv_local_kv_store.dart';
import 'features/background/background_execution_coordinator.dart';
import 'features/background/background_job_repository.dart';
import 'features/logs/log_repository.dart';
import 'features/logs/log_signals.dart';

void initializeBackgroundCoordinator() {
  _backgroundExecutionCoordinator = BackgroundExecutionCoordinator(
    repository: BackgroundJobRepository(store: MmkvLocalKvStore()),
  );
}

BackgroundExecutionCoordinator? _backgroundExecutionCoordinator;

BackgroundExecutionCoordinator get backgroundExecutionCoordinator {
  return _backgroundExecutionCoordinator ??= BackgroundExecutionCoordinator(
    repository: BackgroundJobRepository(store: MmkvLocalKvStore()),
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await MMKV.initialize(logLevel: MMKVLogLevel.Warning);
  final logRepository = LogRepository(store: MmkvLocalKvStore());
  logRepository.restoreInto(logSignals);
  logSignals.onChanged = logRepository.save;
  initializeBackgroundCoordinator();
  runApp(const CainFlowApp());
}
