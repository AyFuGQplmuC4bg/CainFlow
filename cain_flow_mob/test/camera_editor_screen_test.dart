import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cain_flow_mob/features/camera/camera_preview_3d.dart';
import 'package:cain_flow_mob/features/camera/camera_prompt.dart';
import 'package:cain_flow_mob/features/workbench/camera_editor_screen.dart';

void main() {
  testWidgets('CameraPreview3D renders without a reference image', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CameraPreview3D(state: CameraState.front),
        ),
      ),
    );
    expect(find.byType(CameraPreview3D), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('CameraEditorScreen shows the preview and Save action',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: CameraEditorScreen(initial: CameraState.front),
      ),
    );
    expect(find.byType(CameraPreview3D), findsOneWidget);
    // Save action present.
    expect(find.text('Save'), findsOneWidget);
  });

  testWidgets('dragging the preview updates the camera state via callback',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: CameraEditorScreen(initial: CameraState.front)),
    );
    final before = tester
        .widget<CameraPreview3D>(find.byType(CameraPreview3D))
        .state;

    await tester.drag(find.byType(CameraPreview3D), const Offset(60, 0));
    await tester.pump();

    final after = tester
        .widget<CameraPreview3D>(find.byType(CameraPreview3D))
        .state;
    expect(after.yaw, isNot(before.yaw));
  });
}
