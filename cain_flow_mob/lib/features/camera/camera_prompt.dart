import 'dart:math' as math;

/// Camera viewpoint parameters (5D model), ported from the web app's
/// camera-control node. Each field maps to cinematographic language by
/// [CameraPrompt.generate].
class CameraState {
  const CameraState({
    this.pitch = 12,
    this.yaw = 28,
    this.distance = 6.5,
    this.fov = 50,
    this.roll = 0,
  });

  /// Vertical tilt in degrees (−85..85). Positive raises the camera.
  final double pitch;

  /// Horizontal orbit in degrees (−180..180). Positive reveals the right side.
  final double yaw;

  /// Distance to subject (1.4..18). Smaller is a tighter shot.
  final double distance;

  /// Field of view in degrees (18..120). Smaller is more telephoto.
  final double fov;

  /// Dutch-angle roll in degrees (−45..45).
  final double roll;

  static const front = CameraState(
    pitch: 0,
    yaw: 0,
    distance: 6.5,
    fov: 50,
    roll: 0,
  );

  CameraState copyWith({
    double? pitch,
    double? yaw,
    double? distance,
    double? fov,
    double? roll,
  }) {
    return CameraState(
      pitch: pitch ?? this.pitch,
      yaw: yaw ?? this.yaw,
      distance: distance ?? this.distance,
      fov: fov ?? this.fov,
      roll: roll ?? this.roll,
    );
  }

  factory CameraState.fromData(Map<String, dynamic> data) {
    double pick(String key, double fallback) {
      final v = data[key];
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v) ?? fallback;
      return fallback;
    }

    return CameraState(
      pitch: pick('pitch', 12),
      yaw: pick('yaw', 28),
      distance: pick('distance', 6.5),
      fov: pick('fov', 50),
      roll: pick('roll', 0),
    );
  }

  /// Camera params merged into a node's data map (rounded like the web app).
  Map<String, dynamic> toData() {
    return {
      'pitch': _round(pitch, 1),
      'yaw': _round(yaw, 1),
      'distance': _round(distance, 2),
      'fov': _round(fov, 1),
      'roll': _round(roll, 1),
    };
  }
}

/// Bounds for each camera parameter.
class CameraLimits {
  static const pitchMin = -85.0;
  static const pitchMax = 85.0;
  static const yawMin = -180.0;
  static const yawMax = 180.0;
  static const distanceMin = 1.4;
  static const distanceMax = 18.0;
  static const fovMin = 18.0;
  static const fovMax = 120.0;
  static const rollMin = -45.0;
  static const rollMax = 45.0;
}

/// Builds the English camera-instruction prompt from a [CameraState],
/// faithfully ported from the web `generateCameraPrompt`.
abstract final class CameraPrompt {
  static String generate(CameraState s) {
    final spec = _cameraSpec(s);
    final viewpoint = _viewpoint(s.pitch, s.yaw);
    final profile = _distanceProfile(s.distance);
    return [
      'Camera-only transformation of the same subject and scene.',
      'Camera specification: $spec.',
      'Expected view: $viewpoint.',
      'Framing goal: ${profile.goal}.',
      'Strict constraints: keep the same subject identity, pose, proportions, '
          'outfit or materials, lighting, background, and scene layout. Change '
          'only the camera position, viewing angle, framing, lens perspective, '
          'and tilt. ${_sideConsistency(s.yaw)}',
    ].join(' ');
  }

  static String _cameraSpec(CameraState s) {
    final profile = _distanceProfile(s.distance);
    return [
      'yaw ${_fmt(s.yaw, 1)}°: ${_yawPlacement(s.yaw)}',
      'pitch ${_fmt(s.pitch, 1)}°: ${_pitchPlacement(s.pitch)}',
      'distance ${_fmt(s.distance, 2)}: frame as ${profile.shot}',
      'FOV ${_fmt(s.fov, 1)}°: use ${_fovProfile(s.fov)}',
      'roll ${_fmt(s.roll, 1)}°: ${_rollInstruction(s.roll)}',
    ].join('; ');
  }

  static String _viewpoint(double pitch, double yaw) {
    return '${_pitchLabel(pitch)}, ${_yawLabel(yaw)}';
  }

  // --- Pitch -----------------------------------------------------------------

  static String _pitchLabel(double pitch) {
    if (pitch >= 60) return "a bird's-eye top-down angle";
    if (pitch >= 32) return 'a high-angle view';
    if (pitch >= 12) return 'a slightly high-angle view';
    if (pitch > -6) return 'an eye-level view';
    if (pitch >= -16) return 'a slightly low-angle view';
    if (pitch > -38) return 'a low-angle view';
    return "a worm's-eye low-angle view";
  }

  static String _pitchPlacement(double pitch) {
    if (pitch.abs() < 3) return 'keep the camera at eye level';
    if (pitch > 0) {
      return 'raise the camera ${_fmt(pitch.abs(), 1)}° above eye level';
    }
    return 'lower the camera ${_fmt(pitch.abs(), 1)}° below eye level and aim '
        'upward';
  }

  // --- Yaw -------------------------------------------------------------------

  static String _yawDirection(double yaw) => yaw >= 0 ? 'right' : 'left';

  static String _yawLabel(double yaw) {
    final a = yaw.abs();
    final dir = _yawDirection(yaw);
    if (a <= 18) return 'a front view centered on the subject';
    if (a <= 68) {
      return 'a $dir front three-quarter view showing the front and $dir side '
          'of the subject';
    }
    if (a <= 112) {
      return 'a $dir side profile view showing the subject mainly from the side';
    }
    if (a <= 162) {
      return 'a $dir rear three-quarter view showing the back and $dir side of '
          'the subject';
    }
    return 'a straight rear view showing the back of the subject';
  }

  static String _yawPlacement(double yaw) {
    final a = yaw.abs();
    if (a <= 5) return 'keep the camera centered on the subject front';
    if (a >= 175) {
      return 'move the camera to a full rear view behind the subject';
    }
    return "orbit the camera ${_fmt(a, 1)}° toward the subject's "
        '${_yawDirection(yaw)} side from the front reference';
  }

  // --- Distance --------------------------------------------------------------

  static _DistanceProfile _distanceProfile(double distance) {
    if (distance <= 2.4) {
      return const _DistanceProfile(
        'an extreme close-up',
        'fill almost the entire frame with subject details and leave only '
            'minimal background context',
      );
    }
    if (distance <= 4) {
      return const _DistanceProfile(
        'a close-up',
        'keep the subject filling most of the frame with a tight crop and '
            'limited surrounding space',
      );
    }
    if (distance <= 5.8) {
      return const _DistanceProfile(
        'a medium close-up',
        'keep the subject dominant in the frame with only a small amount of '
            'surrounding context',
      );
    }
    if (distance <= 8.2) {
      return const _DistanceProfile(
        'a medium shot',
        'show the subject clearly while retaining some surrounding context',
      );
    }
    if (distance <= 12) {
      return const _DistanceProfile(
        'a full-body or full-object shot',
        'keep the complete subject visible with comfortable margins around it',
      );
    }
    return const _DistanceProfile(
      'a long shot',
      'show the subject smaller within a wider environment and preserve clear '
          'environmental context',
    );
  }

  // --- FOV -------------------------------------------------------------------

  static String _fovProfile(double fov) {
    if (fov < 28) {
      return 'a super-telephoto lens look with strong perspective compression';
    }
    if (fov < 42) {
      return 'a telephoto lens look with compressed perspective and minimal '
          'distortion';
    }
    if (fov < 65) return 'a natural standard-lens perspective';
    if (fov < 86) {
      return 'a wide-angle lens perspective with visible spatial depth';
    }
    if (fov < 108) return 'an ultra-wide-angle perspective with expanded space';
    return 'a fisheye-like ultra-wide perspective with strong edge distortion';
  }

  // --- Roll ------------------------------------------------------------------

  static String _rollInstruction(double roll) {
    final a = roll.abs();
    final dir = roll > 0 ? 'clockwise' : 'counterclockwise';
    if (a < 3) return 'keep roll at 0° and the horizon level';
    if (a < 10) {
      return 'apply a ${_fmt(a, 1)}° $dir roll for a subtle Dutch angle';
    }
    if (a < 20) {
      return 'apply a ${_fmt(a, 1)}° $dir roll for a noticeable Dutch angle';
    }
    return 'apply a ${_fmt(a, 1)}° $dir roll for a strong Dutch angle';
  }

  // --- Side consistency ------------------------------------------------------

  static String _sideConsistency(double yaw) {
    final a = yaw.abs();
    if (a <= 18) {
      return 'Keep the subject front-facing relative to the camera and do not '
          'mirror the image.';
    }
    if (a >= 162) {
      return 'Reach the back view by moving the camera around the subject, not '
          'by flipping or mirroring the image.';
    }
    return "Reveal the subject's ${_yawDirection(yaw)} side by moving the "
        'camera around the subject, not by mirroring the image or swapping '
        'left and right details.';
  }

  static String _fmt(double value, int decimals) =>
      value.toStringAsFixed(decimals);
}

class _DistanceProfile {
  const _DistanceProfile(this.shot, this.goal);
  final String shot;
  final String goal;
}

double _round(double value, int decimals) {
  final f = math.pow(10, decimals);
  return (value * f).round() / f;
}
