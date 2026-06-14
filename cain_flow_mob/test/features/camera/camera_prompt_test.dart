import 'package:cain_flow_mob/features/camera/camera_prompt.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CameraState data round-trip', () {
    test('fromData reads params with fallbacks', () {
      final s = CameraState.fromData(const {
        'pitch': 30,
        'yaw': -90,
        'distance': 3.0,
        'fov': 80,
        'roll': 12,
      });
      expect(s.pitch, 30);
      expect(s.yaw, -90);
      expect(s.distance, 3.0);
      expect(s.fov, 80);
      expect(s.roll, 12);
    });

    test('fromData uses defaults for missing keys', () {
      final s = CameraState.fromData(const {});
      expect(s.pitch, 12);
      expect(s.yaw, 28);
      expect(s.distance, 6.5);
    });

    test('toData rounds to the web app precision', () {
      const s = CameraState(pitch: 12.345, yaw: 28.0, distance: 6.567, fov: 50, roll: 0);
      final data = s.toData();
      expect(data['pitch'], 12.3);
      expect(data['distance'], 6.57);
    });
  });

  group('prompt generation', () {
    test('front default mentions front view and eye level region', () {
      final p = CameraPrompt.generate(CameraState.front);
      expect(p, contains('Camera-only transformation'));
      expect(p, contains('front view centered on the subject'));
      expect(p, contains('do not mirror the image'));
    });

    test('positive yaw reveals the right side', () {
      final p = CameraPrompt.generate(const CameraState(yaw: 90));
      expect(p, contains('right side'));
      expect(p, contains('side profile view'));
    });

    test('negative yaw reveals the left side', () {
      final p = CameraPrompt.generate(const CameraState(yaw: -45));
      expect(p, contains('left'));
    });

    test('high pitch yields a high-angle view', () {
      final p = CameraPrompt.generate(const CameraState(pitch: 45));
      expect(p, contains('high-angle'));
      expect(p, contains('above eye level'));
    });

    test('negative pitch aims upward (low-angle)', () {
      final p = CameraPrompt.generate(const CameraState(pitch: -40));
      expect(p, contains('low-angle'));
      expect(p, contains('aim upward'));
    });

    test('short distance is an extreme close-up', () {
      final p = CameraPrompt.generate(const CameraState(distance: 2.0));
      expect(p, contains('extreme close-up'));
    });

    test('long distance is a long shot', () {
      final p = CameraPrompt.generate(const CameraState(distance: 16));
      expect(p, contains('long shot'));
    });

    test('low fov reads as telephoto, high as fisheye', () {
      expect(
        CameraPrompt.generate(const CameraState(fov: 20)),
        contains('super-telephoto'),
      );
      expect(
        CameraPrompt.generate(const CameraState(fov: 115)),
        contains('fisheye'),
      );
    });

    test('roll produces a Dutch angle with direction', () {
      final cw = CameraPrompt.generate(const CameraState(roll: 25));
      expect(cw, contains('clockwise'));
      expect(cw, contains('strong Dutch angle'));
      final ccw = CameraPrompt.generate(const CameraState(roll: -8));
      expect(ccw, contains('counterclockwise'));
    });

    test('rear view instructs orbiting, not flipping', () {
      final p = CameraPrompt.generate(const CameraState(yaw: 175));
      expect(p, contains('rear view'));
      expect(p, contains('not by flipping or mirroring'));
    });
  });
}
