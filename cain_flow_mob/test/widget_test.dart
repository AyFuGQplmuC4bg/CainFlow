import 'package:cain_flow_mob/app/cain_flow_app.dart';
import 'package:cain_flow_mob/features/execution/execution_signals.dart';
import 'package:cain_flow_mob/features/workbench/workbench_signals.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cain_flow_mob/features/workbench/workbench_screen.dart';

void main() {
  testWidgets('renders CainFlow workbench shell', (tester) async {
    await tester.pumpWidget(const CainFlowApp());

    expect(find.text('CAINFLOW'), findsOneWidget);
    expect(find.text('Untitled Workflow'), findsAtLeastNWidgets(1));
    expect(find.text('Workflows'), findsOneWidget);
    expect(find.text('Image Generate'), findsOneWidget);
    expect(find.text('Run'), findsOneWidget);
    expect(find.byTooltip('Settings'), findsOneWidget);
    expect(find.byTooltip('Logs'), findsOneWidget);
  });

  testWidgets('canvas status chip reflects execution state', (tester) async {
    executionSignals.reset(const ['node_text_prompt']);
    addTearDown(() => executionSignals.reset(const []));

    await tester.pumpWidget(
      const MaterialApp(home: WorkbenchScreen()),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Ready -'), findsOneWidget);

    executionSignals.markWorkflowRunning();
    // A running workflow starts a 1s ticker + spinner, so the tree never
    // settles; pump a frame instead of pumpAndSettle.
    await tester.pump();
    expect(find.textContaining('Running -'), findsOneWidget);

    executionSignals.markWorkflowFailed('boom');
    await tester.pump();
    expect(find.textContaining('Failed -'), findsOneWidget);
  });

  testWidgets('inspector shows selected node execution status', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    workbenchSignals.selectNode('node_text_prompt');
    executionSignals.reset(const ['node_text_prompt']);
    executionSignals.markNode(
      'node_text_prompt',
      NodeRunState.failed,
      message: 'request failed',
    );
    addTearDown(() {
      workbenchSignals.clearSelection();
      executionSignals.reset(const []);
    });

    await tester.pumpWidget(
      const MaterialApp(home: WorkbenchScreen()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Status: Failed'), findsOneWidget);
    expect(find.text('request failed'), findsOneWidget);
  });
}
