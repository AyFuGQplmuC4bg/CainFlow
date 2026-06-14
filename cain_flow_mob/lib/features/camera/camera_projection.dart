import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import 'package:vector_math/vector_math_64.dart';

import 'camera_prompt.dart';

/// World position of the subject's center, matching the web app's
/// `SUBJECT_TARGET` (the camera always looks here).
const subjectCenter = (x: 0.0, y: 1.2, z: 0.0);

/// Half-size of the subject plane in world units before aspect scaling
/// (web uses a 3x3 PlaneGeometry, so half-extent is 1.5).
const double subjectHalfSize = 1.5;

const double _near = 0.1;
const double _far = 100.0;

/// Projects world-space points onto a preview viewport using the exact camera
/// math of the web `applyCameraStateToCamera`: the camera orbits the subject by
/// pitch/yaw at a given distance, looks at the subject center, applies a Dutch
/// roll about the view axis, and uses [CameraState.fov] as the vertical FOV.
///
/// Pure and allocation-light so it can drive both live painting and an
/// off-screen snapshot, and be unit-tested without a render surface.
class CameraProjection {
  CameraProjection(this.state, this.viewport)
      : _eye = _cameraPosition(state),
        _matrix = _buildMatrix(state, viewport);

  final CameraState state;
  final Size viewport;

  final Vector3 _eye;
  final Matrix4 _matrix;

  /// Camera eye position in world space.
  Vector3 get eye => _eye;

  /// Camera world position from the 5D state (spherical orbit around the
  /// subject), identical to the web formula.
  static Vector3 _cameraPosition(CameraState s) {
    final pitchRad = _deg2rad(s.pitch);
    final yawRad = _deg2rad(s.yaw);
    final cosPitch = math.cos(pitchRad);
    return Vector3(
      s.distance * cosPitch * math.sin(yawRad),
      s.distance * math.sin(pitchRad) + subjectCenter.y,
      s.distance * cosPitch * math.cos(yawRad),
    );
  }

  static Matrix4 _buildMatrix(CameraState s, Size viewport) {
    final eye = _cameraPosition(s);
    final target = Vector3(subjectCenter.x, subjectCenter.y, subjectCenter.z);
    final view = makeViewMatrix(eye, target, Vector3(0, 1, 0));

    // Dutch roll: web calls camera.rotateZ(roll) after lookAt, which rotates
    // the camera about its own forward axis. In eye space that is a
    // pre-multiply by a rotation of -roll about Z.
    final roll = Matrix4.rotationZ(-_deg2rad(s.roll));

    final aspect = viewport.height == 0
        ? 1.0
        : viewport.width / viewport.height;
    final proj = makePerspectiveMatrix(_deg2rad(s.fov), aspect, _near, _far);

    return proj * roll * view;
  }

  /// True when the camera sits behind the subject plane (normal +Z), so the
  /// front image is not visible and a BACK placeholder should be drawn.
  bool get subjectFacingAway => _eye.z < 0;

  /// Projects a world point to viewport pixels plus its clip-space w (depth).
  /// `w <= 0` means the point is at or behind the camera and should not be
  /// drawn directly.
  ({Offset screen, double w}) projectWithDepth(Vector3 world) {
    final clip = _matrix.transform(Vector4(world.x, world.y, world.z, 1));
    final w = clip.w;
    if (w == 0) {
      return (screen: Offset.zero, w: 0);
    }
    final ndcX = clip.x / w;
    final ndcY = clip.y / w;
    final sx = (ndcX * 0.5 + 0.5) * viewport.width;
    final sy = (1 - (ndcY * 0.5 + 0.5)) * viewport.height;
    return (screen: Offset(sx, sy), w: w);
  }

  /// Projects a world point to viewport pixels.
  Offset projectVertex(Vector3 world) => projectWithDepth(world).screen;

  static double _deg2rad(double deg) => deg * math.pi / 180.0;
}
