import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';

import 'package:cain_flow_mob/features/camera/camera_projection.dart';
import 'package:cain_flow_mob/features/camera/camera_prompt.dart';

void main() {
  const viewport = Size(400, 300);

  // The four corners of the subject plane (XY, normal +Z), centered at
  // subjectCenter, used to reason about where the image lands on screen.
  List<Vector3> planeCorners() {
    final cx = subjectCenter.x;
    final cy = subjectCenter.y;
    const h = subjectHalfSize;
    return [
      Vector3(cx - h, cy + h, 0), // top-left
      Vector3(cx + h, cy + h, 0), // top-right
      Vector3(cx + h, cy - h, 0), // bottom-right
      Vector3(cx - h, cy - h, 0), // bottom-left
    ];
  }

  group('CameraProjection', () {
    test('front view keeps the subject facing the camera', () {
      const front = CameraState(pitch: 0, yaw: 0, distance: 6.5, fov: 50, roll: 0);
      final proj = CameraProjection(front, viewport);
      expect(proj.subjectFacingAway, isFalse);
      // Camera sits on +Z looking toward origin.
      expect(proj.eye.z, greaterThan(0));
    });

    test('subject center projects near the viewport center for a front view', () {
      const front = CameraState(pitch: 0, yaw: 0, distance: 6.5, fov: 50, roll: 0);
      final proj = CameraProjection(front, viewport);
      final center = proj.projectVertex(
        Vector3(subjectCenter.x, subjectCenter.y, subjectCenter.z),
      );
      expect(center.dx, closeTo(viewport.width / 2, 1.0));
      expect(center.dy, closeTo(viewport.height / 2, 1.0));
    });

    test('rear view (yaw 180) marks the subject as facing away', () {
      const rear = CameraState(pitch: 0, yaw: 180, distance: 6.5, fov: 50, roll: 0);
      final proj = CameraProjection(rear, viewport);
      expect(proj.subjectFacingAway, isTrue);
      expect(proj.eye.z, lessThan(0));
    });

    test('wider FOV makes the subject smaller on screen', () {
      const narrow = CameraState(pitch: 0, yaw: 0, distance: 6.5, fov: 35, roll: 0);
      const wide = CameraState(pitch: 0, yaw: 0, distance: 6.5, fov: 90, roll: 0);

      double screenWidth(CameraState s) {
        final proj = CameraProjection(s, viewport);
        final corners = planeCorners().map(proj.projectVertex).toList();
        final left = corners.map((c) => c.dx).reduce((a, b) => a < b ? a : b);
        final right = corners.map((c) => c.dx).reduce((a, b) => a > b ? a : b);
        return right - left;
      }

      expect(screenWidth(wide), lessThan(screenWidth(narrow)));
    });

    test('all front-view corners project with positive depth', () {
      const front = CameraState(pitch: 0, yaw: 0, distance: 6.5, fov: 50, roll: 0);
      final proj = CameraProjection(front, viewport);
      for (final corner in planeCorners()) {
        expect(proj.projectWithDepth(corner).w, greaterThan(0));
      }
    });

    test('front view corners are symmetric about the viewport center', () {
      const front = CameraState(pitch: 0, yaw: 0, distance: 6.5, fov: 50, roll: 0);
      final proj = CameraProjection(front, viewport);
      final corners = planeCorners().map(proj.projectVertex).toList();
      final left = corners.map((c) => c.dx).reduce((a, b) => a < b ? a : b);
      final right = corners.map((c) => c.dx).reduce((a, b) => a > b ? a : b);
      expect((left + right) / 2, closeTo(viewport.width / 2, 1.0));
    });
  });
}
