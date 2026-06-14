import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

import 'camera_projection.dart';
import 'camera_prompt.dart';

/// Plane subdivision per axis. ~12x12 quads keep the textured projection
/// perspective-correct enough while staying a single cheap draw call.
const int _gridSegments = 12;

/// Colors for the preview scene, pulled from the active theme so the preview
/// matches the editor, with a const dark default for off-screen snapshots.
class CameraPreviewPalette {
  const CameraPreviewPalette({
    required this.background,
    required this.grid,
    required this.frame,
    required this.backPanel,
    required this.placeholderPanel,
    required this.label,
  });

  final Color background;
  final Color grid;
  final Color frame;
  final Color backPanel;
  final Color placeholderPanel;
  final Color label;

  static const dark = CameraPreviewPalette(
    background: Color(0xFF0F1722),
    grid: Color(0x33334155),
    frame: Color(0xFFF8FAFC),
    backPanel: Color(0xFF1B2330),
    placeholderPanel: Color(0xFF16202D),
    label: Color(0xFFE2E8F0),
  );

  factory CameraPreviewPalette.fromTheme(ThemeData theme) {
    final scheme = theme.colorScheme;
    return CameraPreviewPalette(
      background: const Color(0xFF0F1722),
      grid: scheme.outlineVariant.withValues(alpha: 0.35),
      frame: const Color(0xFFF8FAFC),
      backPanel: const Color(0xFF1B2330),
      placeholderPanel: const Color(0xFF16202D),
      label: const Color(0xFFE2E8F0),
    );
  }
}

/// Live first-person preview of the camera viewpoint: renders the upstream
/// reference image as a billboard the camera orbits, mirroring the web 3D
/// editor. Drag to orbit (yaw/pitch), pinch to dolly (distance); changes are
/// reported via [onStateChanged] so sliders and the prompt stay in sync.
class CameraPreview3D extends StatefulWidget {
  const CameraPreview3D({
    super.key,
    required this.state,
    this.referenceImage,
    this.onStateChanged,
  });

  final CameraState state;
  final ui.Image? referenceImage;
  final ValueChanged<CameraState>? onStateChanged;

  @override
  State<CameraPreview3D> createState() => _CameraPreview3DState();
}

class _CameraPreview3DState extends State<CameraPreview3D> {
  double _scaleStartDistance = 0;

  void _onScaleStart(ScaleStartDetails details) {
    _scaleStartDistance = widget.state.distance;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final cb = widget.onStateChanged;
    if (cb == null) return;
    if (details.scale != 1.0) {
      // Pinch: inverse maps a spread (scale>1) to a smaller distance.
      final next = (_scaleStartDistance / details.scale)
          .clamp(CameraLimits.distanceMin, CameraLimits.distanceMax);
      cb(widget.state.copyWith(distance: next));
    } else {
      // Single-finger drag: orbit. focalPointDelta is per-frame movement.
      final d = details.focalPointDelta;
      final yaw = _wrapYaw(widget.state.yaw - d.dx * 0.35);
      final pitch = (widget.state.pitch + d.dy * 0.25)
          .clamp(CameraLimits.pitchMin, CameraLimits.pitchMax);
      cb(widget.state.copyWith(yaw: yaw, pitch: pitch));
    }
  }

  double _wrapYaw(double yaw) {
    var v = yaw;
    while (v > 180) {
      v -= 360;
    }
    while (v < -180) {
      v += 360;
    }
    return v;
  }

  @override
  Widget build(BuildContext context) {
    final palette = CameraPreviewPalette.fromTheme(Theme.of(context));
    return GestureDetector(
      onScaleStart: widget.onStateChanged == null ? null : _onScaleStart,
      onScaleUpdate: widget.onStateChanged == null ? null : _onScaleUpdate,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: AspectRatio(
          aspectRatio: 4 / 3,
          child: CustomPaint(
            painter: CameraScenePainter(
              state: widget.state,
              referenceImage: widget.referenceImage,
              palette: palette,
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

/// Paints the camera-preview scene: ground grid, the subject billboard (the
/// reference image projected through [CameraProjection], or a BACK panel when
/// the camera is behind it), and the white frame. Shared by the live widget
/// and the off-screen snapshot via [paintCameraScene].
class CameraScenePainter extends CustomPainter {
  CameraScenePainter({
    required this.state,
    required this.referenceImage,
    required this.palette,
  });

  final CameraState state;
  final ui.Image? referenceImage;
  final CameraPreviewPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    paintCameraScene(
      canvas: canvas,
      size: size,
      state: state,
      referenceImage: referenceImage,
      palette: palette,
    );
  }

  @override
  bool shouldRepaint(covariant CameraScenePainter old) =>
      old.state != state ||
      old.referenceImage != referenceImage ||
      old.palette != palette;
}

/// Draws the full preview scene onto [canvas]. Extracted as a free function so
/// the editor can replay the exact same frame into a [ui.PictureRecorder] for
/// the node-card snapshot.
void paintCameraScene({
  required Canvas canvas,
  required Size size,
  required CameraState state,
  required ui.Image? referenceImage,
  required CameraPreviewPalette palette,
}) {
  canvas.drawRect(
    Offset.zero & size,
    Paint()..color = palette.background,
  );

  final projection = CameraProjection(state, size);
  _paintGround(canvas, projection, palette);

  if (projection.subjectFacingAway || referenceImage == null) {
    _paintPlaceholderOrBack(
      canvas,
      projection,
      palette,
      facingAway: projection.subjectFacingAway,
    );
  } else {
    _paintTexturedSubject(canvas, projection, referenceImage);
  }

  _paintFrame(canvas, projection, palette);
}

/// Ground grid lines on the XZ plane (y = subject base), giving spatial depth.
void _paintGround(
  Canvas canvas,
  CameraProjection projection,
  CameraPreviewPalette palette,
) {
  const half = 6.0;
  const step = 1.0;
  final y = subjectCenter.y - 1.65; // a touch below the subject base
  final paint = Paint()
    ..color = palette.grid
    ..strokeWidth = 1
    ..style = PaintingStyle.stroke;

  for (double i = -half; i <= half; i += step) {
    _drawWorldSegment(
      canvas,
      projection,
      Vector3(i, y, -half),
      Vector3(i, y, half),
      paint,
    );
    _drawWorldSegment(
      canvas,
      projection,
      Vector3(-half, y, i),
      Vector3(half, y, i),
      paint,
    );
  }
}

/// Draws a world-space segment, skipping it when either endpoint is behind the
/// camera (a robust-enough near-plane guard for this simple scene).
void _drawWorldSegment(
  Canvas canvas,
  CameraProjection projection,
  Vector3 a,
  Vector3 b,
  Paint paint,
) {
  final pa = projection.projectWithDepth(a);
  final pb = projection.projectWithDepth(b);
  if (pa.w <= 0 || pb.w <= 0) return;
  canvas.drawLine(pa.screen, pb.screen, paint);
}

/// Projects and triangulates the subject plane, then maps the reference image
/// onto it with a single [Canvas.drawVertices] call. Subdivision keeps the
/// perspective mapping correct across the quad.
void _paintTexturedSubject(
  Canvas canvas,
  CameraProjection projection,
  ui.Image image,
) {
  const n = _gridSegments;
  const h = subjectHalfSize;
  final cx = subjectCenter.x;
  final cy = subjectCenter.y;

  final positions = <Offset>[];
  final texCoords = <Offset>[];
  final indices = <int>[];

  // Grid of (n+1)x(n+1) vertices across the plane.
  for (int row = 0; row <= n; row++) {
    final v = row / n; // 0 at top, 1 at bottom
    final worldY = cy + h - 2 * h * v;
    for (int col = 0; col <= n; col++) {
      final u = col / n; // 0 at left, 1 at right
      final worldX = cx - h + 2 * h * u;
      positions.add(projection.projectVertex(Vector3(worldX, worldY, 0)));
      texCoords.add(Offset(u * image.width, v * image.height));
    }
  }

  int idx(int row, int col) => row * (n + 1) + col;
  for (int row = 0; row < n; row++) {
    for (int col = 0; col < n; col++) {
      final tl = idx(row, col);
      final tr = idx(row, col + 1);
      final bl = idx(row + 1, col);
      final br = idx(row + 1, col + 1);
      indices.addAll([tl, tr, bl, tr, br, bl]);
    }
  }

  final vertices = ui.Vertices(
    ui.VertexMode.triangles,
    positions,
    textureCoordinates: texCoords,
    indices: indices,
  );
  final shader = ui.ImageShader(
    image,
    TileMode.clamp,
    TileMode.clamp,
    Matrix4.identity().storage,
  );
  canvas.drawVertices(
    vertices,
    BlendMode.srcOver,
    Paint()..shader = shader,
  );
}

/// Fills the projected plane quad with a solid panel and centered label, used
/// for the BACK face and the "no upstream image" placeholder.
void _paintPlaceholderOrBack(
  Canvas canvas,
  CameraProjection projection,
  CameraPreviewPalette palette, {
  required bool facingAway,
}) {
  const h = subjectHalfSize;
  final cx = subjectCenter.x;
  final cy = subjectCenter.y;
  final corners = [
    projection.projectWithDepth(Vector3(cx - h, cy + h, 0)),
    projection.projectWithDepth(Vector3(cx + h, cy + h, 0)),
    projection.projectWithDepth(Vector3(cx + h, cy - h, 0)),
    projection.projectWithDepth(Vector3(cx - h, cy - h, 0)),
  ];
  if (corners.any((c) => c.w <= 0)) return;

  final path = Path()..moveTo(corners[0].screen.dx, corners[0].screen.dy);
  for (final c in corners.skip(1)) {
    path.lineTo(c.screen.dx, c.screen.dy);
  }
  path.close();
  canvas.drawPath(
    path,
    Paint()
      ..color = facingAway ? palette.backPanel : palette.placeholderPanel
      ..style = PaintingStyle.fill,
  );

  final center = Offset(
    corners.map((c) => c.screen.dx).reduce((a, b) => a + b) / 4,
    corners.map((c) => c.screen.dy).reduce((a, b) => a + b) / 4,
  );
  _paintLabel(
    canvas,
    center,
    facingAway ? 'BACK' : '等待参考图输入',
    palette.label,
    facingAway ? 28 : 14,
  );
}

void _paintLabel(
  Canvas canvas,
  Offset center,
  String text,
  Color color,
  double fontSize,
) {
  final tp = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        color: color,
        fontSize: fontSize,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.5,
      ),
    ),
    textDirection: TextDirection.ltr,
    textAlign: TextAlign.center,
  )..layout();
  tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
}

/// White outline around the projected subject plane (web's EdgesGeometry).
void _paintFrame(
  Canvas canvas,
  CameraProjection projection,
  CameraPreviewPalette palette,
) {
  const h = subjectHalfSize;
  final cx = subjectCenter.x;
  final cy = subjectCenter.y;
  final corners = [
    projection.projectWithDepth(Vector3(cx - h, cy + h, 0)),
    projection.projectWithDepth(Vector3(cx + h, cy + h, 0)),
    projection.projectWithDepth(Vector3(cx + h, cy - h, 0)),
    projection.projectWithDepth(Vector3(cx - h, cy - h, 0)),
  ];
  if (corners.any((c) => c.w <= 0)) return;

  final path = Path()..moveTo(corners[0].screen.dx, corners[0].screen.dy);
  for (final c in corners.skip(1)) {
    path.lineTo(c.screen.dx, c.screen.dy);
  }
  path.close();
  canvas.drawPath(
    path,
    Paint()
      ..color = palette.frame.withValues(alpha: 0.9)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke,
  );
}
