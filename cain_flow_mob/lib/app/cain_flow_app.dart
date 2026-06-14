import 'package:flutter/material.dart';
import 'package:signals/signals_flutter.dart';

import '../features/workbench/workbench_screen.dart';
import '../l10n/app_localizations.dart';
import '../l10n/locale_signal.dart';
import 'theme/cain_flow_theme.dart';

class CainFlowApp extends SignalWidget {
  const CainFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CainFlow',
      debugShowCheckedModeBanner: false,
      theme: buildCainFlowTheme(),
      locale: localeSignal.value,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const WorkbenchScreen(),
    );
  }
}
