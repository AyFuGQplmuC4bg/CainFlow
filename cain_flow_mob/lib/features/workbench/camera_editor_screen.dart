import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../camera/camera_preview_3d.dart';
import '../camera/camera_prompt.dart';
import '../media/image_decoder.dart';
import '../media/media_repository.dart';

/// Full-screen editor for a CameraControl node's 5D viewpoint. Returns the
/// updated camera data map (pitch/yaw/distance/fov/roll, plus a `cameraPreview`
/// snapshot payload) on save, or null on cancel. Shows a live 3D preview of the
/// camera viewpoint and the generated prompt as the sliders move.
class CameraEditorScreen extends StatefulWidget {
  const CameraEditorScreen({
    super.key,
    required this.initial,
    this.referenceImagePayload,
    this.media,
  });

  final CameraState initial;

  /// Upstream image payload connected to the node's `image` port, projected
  /// onto the preview billboard. Null when nothing is connected.
  final Object? referenceImagePayload;

  /// Used to resolve asset payloads to bytes. Null in tests/previews.
  final MediaRepository? media;

  @override
  State<CameraEditorScreen> createState() => _CameraEditorScreenState();
}

class _CameraEditorScreenState extends State<CameraEditorScreen> {
  late CameraState _state;
  ui.Image? _referenceImage;

  @override
  void initState() {
    super.initState();
    _state = widget.initial;
    _loadReferenceImage();
  }

  Future<void> _loadReferenceImage() async {
    final media = widget.media;
    if (media == null || widget.referenceImagePayload == null) return;
    final image = await decodeImagePayload(widget.referenceImagePayload, media);
    if (!mounted || image == null) return;
    setState(() => _referenceImage = image);
  }

  @override
  void dispose() {
    _referenceImage?.dispose();
    super.dispose();
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
              onPressed: _save,
              child: const Text('Save'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          CameraPreview3D(
            state: _state,
            referenceImage: _referenceImage,
            onStateChanged: (next) => setState(() => _state = next),
          ),
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

  /// Saves the camera data, attaching a `cameraPreview` asset payload rendered
  /// off-screen from the current viewpoint so the node card can show it.
  Future<void> _save() async {
    final data = _state.toData();
    final preview = await _captureSnapshotPayload();
    if (preview != null) {
      data['cameraPreview'] = preview;
    }
    if (!mounted) return;
    Navigator.of(context).pop(data);
  }

  /// Replays the live preview frame into an off-screen recorder and persists it
  /// as a PNG asset, returning its payload (`{kind: asset, ...}`) or null.
  Future<Map<String, dynamic>?> _captureSnapshotPayload() async {
    final media = widget.media;
    if (media == null) return null;
    try {
      const size = Size(360, 270);
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, Offset.zero & size);
      paintCameraScene(
        canvas: canvas,
        size: size,
        state: _state,
        referenceImage: _referenceImage,
        palette: CameraPreviewPalette.dark,
      );
      final picture = recorder.endRecording();
      final image = await picture.toImage(size.width.toInt(), size.height.toInt());
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      picture.dispose();
      image.dispose();
      if (bytes == null) return null;
      final asset = await media.saveBytes(
        workflowId: '',
        fileName: 'camera-preview.png',
        mimeType: 'image/png',
        bytes: bytes.buffer.asUint8List(),
      );
      return {
        'kind': 'asset',
        'assetId': asset.id,
        'relativePath': asset.relativePath,
        'thumbnailRelativePath': asset.thumbnailRelativePath,
        'mimeType': asset.mimeType,
        'byteLength': asset.byteLength,
      };
    } catch (_) {
      return null;
    }
  }
}
