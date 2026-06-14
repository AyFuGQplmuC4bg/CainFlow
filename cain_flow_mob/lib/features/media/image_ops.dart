import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// How an image should be fit when resizing to a target box.
enum ImageFit { stretch, contain, cover }

/// Layout for merging multiple images into one.
enum MergeLayout { horizontal, vertical, grid }

/// Pure image-processing helpers built on the `image` package. All methods
/// operate on encoded bytes in / encoded PNG bytes out so callers can store
/// results directly through `MediaRepository`.
abstract final class ImageOps {
  static img.Image decode(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw const FormatException('Unsupported or corrupt image data');
    }
    return decoded;
  }

  static Uint8List encodePng(img.Image image) {
    return Uint8List.fromList(img.encodePng(image));
  }

  /// Resizes [bytes] to fit [width]x[height] using [fit].
  static Uint8List resize(
    Uint8List bytes, {
    required int width,
    required int height,
    ImageFit fit = ImageFit.contain,
  }) {
    final src = decode(bytes);
    final result = switch (fit) {
      ImageFit.stretch => img.copyResize(src, width: width, height: height),
      ImageFit.contain => _resizeContain(src, width, height),
      ImageFit.cover => img.copyResizeCropSquare(src, size: width)
          .let((sq) => height == width
              ? sq
              : img.copyResize(sq, width: width, height: height)),
    };
    return encodePng(result);
  }

  /// Crops a rectangular region, clamped to the image bounds.
  static Uint8List crop(
    Uint8List bytes, {
    required int x,
    required int y,
    required int width,
    required int height,
  }) {
    final src = decode(bytes);
    final cx = x.clamp(0, src.width - 1);
    final cy = y.clamp(0, src.height - 1);
    final cw = width.clamp(1, src.width - cx);
    final ch = height.clamp(1, src.height - cy);
    return encodePng(img.copyCrop(src, x: cx, y: cy, width: cw, height: ch));
  }

  /// Draws annotation shapes onto [bytes] and returns a new PNG. Each shape is
  /// `{type: rect|line, x1, y1, x2, y2, color}` with `color` an ARGB int.
  static Uint8List annotate(
    Uint8List bytes,
    List<Map<String, dynamic>> shapes, {
    int strokeColor = 0xFFFF3B30,
    int thickness = 3,
  }) {
    final image = decode(bytes);
    for (final shape in shapes) {
      final type = shape['type']?.toString() ?? 'rect';
      final x1 = (shape['x1'] as num?)?.round() ?? 0;
      final y1 = (shape['y1'] as num?)?.round() ?? 0;
      final x2 = (shape['x2'] as num?)?.round() ?? 0;
      final y2 = (shape['y2'] as num?)?.round() ?? 0;
      final argb = (shape['color'] as num?)?.toInt() ?? strokeColor;
      final color = img.ColorUint32.rgba(
        (argb >> 16) & 0xFF,
        (argb >> 8) & 0xFF,
        argb & 0xFF,
        (argb >> 24) & 0xFF,
      );
      if (type == 'line') {
        img.drawLine(image, x1: x1, y1: y1, x2: x2, y2: y2, color: color,
            thickness: thickness);
      } else {
        img.drawRect(image, x1: x1, y1: y1, x2: x2, y2: y2, color: color,
            thickness: thickness);
      }
    }
    return encodePng(image);
  }

  /// Creates a thumbnail no larger than [maxSize] on its longest edge,  /// preserving aspect ratio.
  static Uint8List thumbnail(Uint8List bytes, {int maxSize = 256}) {
    final src = decode(bytes);
    final longest = src.width >= src.height ? src.width : src.height;
    if (longest <= maxSize) return encodePng(src);
    final scale = maxSize / longest;
    return encodePng(
      img.copyResize(
        src,
        width: (src.width * scale).round(),
        height: (src.height * scale).round(),
      ),
    );
  }

  /// Merges [images] into one PNG using [layout]. Images are normalized to a
  /// common cell size (the max dimensions across inputs).
  static Uint8List merge(
    List<Uint8List> images, {
    MergeLayout layout = MergeLayout.horizontal,
    int gap = 8,
    int background = 0xFF202020,
  }) {
    if (images.isEmpty) {
      throw ArgumentError('merge requires at least one image');
    }
    final decoded = images.map(decode).toList();
    final cellW = decoded.map((i) => i.width).reduce(_max);
    final cellH = decoded.map((i) => i.height).reduce(_max);
    final count = decoded.length;

    final (cols, rows) = switch (layout) {
      MergeLayout.horizontal => (count, 1),
      MergeLayout.vertical => (1, count),
      MergeLayout.grid => _gridDims(count),
    };

    final canvasW = cols * cellW + (cols + 1) * gap;
    final canvasH = rows * cellH + (rows + 1) * gap;
    final canvas = img.Image(width: canvasW, height: canvasH)
      ..clear(img.ColorUint32.rgba(
        (background >> 16) & 0xFF,
        (background >> 8) & 0xFF,
        background & 0xFF,
        (background >> 24) & 0xFF,
      ));

    for (var i = 0; i < decoded.length; i++) {
      final col = i % cols;
      final row = i ~/ cols;
      final dstX = gap + col * (cellW + gap);
      final dstY = gap + row * (cellH + gap);
      img.compositeImage(canvas, decoded[i], dstX: dstX, dstY: dstY);
    }
    return encodePng(canvas);
  }

  /// Places two images side by side for visual comparison.
  static Uint8List compare(Uint8List a, Uint8List b) {
    return merge([a, b], layout: MergeLayout.horizontal);
  }

  static img.Image _resizeContain(img.Image src, int width, int height) {
    final scale = (width / src.width) <= (height / src.height)
        ? width / src.width
        : height / src.height;
    return img.copyResize(
      src,
      width: (src.width * scale).round(),
      height: (src.height * scale).round(),
    );
  }

  static (int, int) _gridDims(int count) {
    var cols = 1;
    while (cols * cols < count) {
      cols += 1;
    }
    final rows = (count + cols - 1) ~/ cols;
    return (cols, rows);
  }
}

int _max(int a, int b) => a >= b ? a : b;

extension _Let<T> on T {
  R let<R>(R Function(T) fn) => fn(this);
}
