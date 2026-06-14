import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../camera/camera_prompt.dart';

/// Full-screen editor for a CameraControl node's 5D viewpoint. Returns the
/// updated camera data map (pitch/yaw/distance/fov/roll) on save, or null on
/// cancel. Shows the generated prompt live as the sliders move.
class CameraEditorScreen extends StatefulWidget {
  const CameraEditorScreen({super.key, required this.initial});

  final CameraState initial;

  @override
  State<CameraEditorScreen> createState() => _CameraEditorScreenState();
}

class _CameraEditorScreenState extends State<CameraEditorScreen> {
  late CameraState _state;

  @override
  void initState() {
    super.initState();
    _state = widget.initial;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final prompt = CameraPrompt.generate(_state);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Viewpoint'),
        actions: [
          TextButton(
            onPressed: () => setState(() => _state = CameraState.front),
            child: const Text('Reset'),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(_state.toData()),
              child: const Text('Save'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _CameraDiagram(state: _state),
          const SizedBox(height: 16),
          _slider(
            label: 'Pitch (俯仰)',
            value: _state.pitch,
            min: CameraLimits.pitchMin,
            max: CameraLimits.pitchMax,
            unit: '°',
            onChanged: (v) => setState(() => _state = _state.copyWith(pitch: v)),
          ),
          _slider(
            label: 'Yaw (偏航)',
            value: _state.yaw,
            min: CameraLimits.yawMin,
            max: CameraLimits.yawMax,
            unit: '°',
            onChanged: (v) => setState(() => _state = _state.copyWith(yaw: v)),
          ),
          _slider(
            label: 'Distance (距离)',
            value: _state.distance,
            min: CameraLimits.distanceMin,
            max: CameraLimits.distanceMax,
            unit: '',
            decimals: 2,
            onChanged: (v) =>
                setState(() => _state = _state.copyWith(distance: v)),
          ),
          _slider(
            label: 'FOV (视野)',
            value: _state.fov,
            min: CameraLimits.fovMin,
            max: CameraLimits.fovMax,
            unit: '°',
            onChanged: (v) => setState(() => _state = _state.copyWith(fov: v)),
          ),
          _slider(
            label: 'Roll (翻滚)',
            value: _state.roll,
            min: CameraLimits.rollMin,
            max: CameraLimits.rollMax,
            unit: '°',
            onChanged: (v) => setState(() => _state = _state.copyWith(roll: v)),
          ),
          const SizedBox(height: 16),
          Text('Generated prompt', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: SelectableText(
              prompt,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Widget _slider({
    required String label,
    required double value,
    required double min,
    required double max,
    required String unit,
    required ValueChanged<double> onChanged,
    int decimals = 1,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: theme.textTheme.bodyMedium),
            Text(
              '${value.toStringAsFixed(decimals)}$unit',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontFeatures: const [],
              ),
            ),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

/// Lightweight 2D diagram: a top-down ring showing the camera's yaw position
/// and a label for the resulting shot, giving quick spatial feedback without a
/// full 3D engine.
class _CameraDiagram extends StatelessWidget {
  const _CameraDiagram({required this.state});

  final CameraState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 160,
      child: CustomPaint(
        painter: _DiagramPainter(
          state: state,
          subjectColor: theme.colorScheme.primary,
          cameraColor: theme.colorScheme.secondary,
          gridColor: theme.colorScheme.outlineVariant,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _DiagramPainter extends CustomPainter {
  _DiagramPainter({
    required this.state,
    required this.subjectColor,
    required this.cameraColor,
    required this.gridColor,
  });

  final CameraState state;
  final Color subjectColor;
  final Color cameraColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = size.shortestSide / 2 - 16;

    // Orbit ring.
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = gridColor;
    canvas.drawCircle(center, maxR, ring);

    // Subject at center.
    canvas.drawCircle(center, 6, Paint()..color = subjectColor);

    // Camera position from yaw + distance (top-down: yaw 0 = front/bottom).
    final r = maxR *
        ((state.distance - CameraLimits.distanceMin) /
                (CameraLimits.distanceMax - CameraLimits.distanceMin))
            .clamp(0.2, 1.0);
    final yawRad = state.yaw * math.pi / 180;
    final camPos = Offset(
      center.dx + r * math.sin(yawRad),
      center.dy + r * math.cos(yawRad),
    );
    // Line subject -> camera.
    canvas.drawLine(
      center,
      camPos,
      Paint()
        ..color = cameraColor
        ..strokeWidth = 2,
    );
    canvas.drawCircle(camPos, 7, Paint()..color = cameraColor);
  }

  @override
  bool shouldRepaint(covariant _DiagramPainter old) =>
      old.state.yaw != state.yaw || old.state.distance != state.distance;
}
