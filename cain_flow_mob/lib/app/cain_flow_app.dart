import 'package:flutter/material.dart';

import '../features/workbench/workbench_screen.dart';
import 'theme/cain_flow_theme.dart';

class CainFlowApp extends StatelessWidget {
  const CainFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CainFlow',
      debugShowCheckedModeBanner: false,
      theme: buildCainFlowTheme(),
      home: const WorkbenchScreen(),
    );
  }
}
