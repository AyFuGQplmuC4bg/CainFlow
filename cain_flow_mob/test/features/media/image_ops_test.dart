import 'dart:typed_data';

import 'package:cain_flow_mob/features/media/image_ops.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  // A solid-color PNG of the given size.
  Uint8List solid(int w, int h, {int r = 255, int g = 0, int b = 0}) {
    final image = img.Image(width: w, height: h)
      ..clear(img.ColorRgb8(r, g, b));
    return Uint8List.fromList(img.encodePng(image));
  }

  test('resize stretch produces exact target dimensions', () {
    final out = ImageOps.resize(
      solid(40, 20),
      width: 10,
      height: 30,
      fit: ImageFit.stretch,
    );
    final decoded = img.decodePng(out)!;
    expect(decoded.width, 10);
    expect(decoded.height, 30);
  });

  test('resize contain preserves aspect ratio within the box', () {
    final out = ImageOps.resize(
      solid(40, 20),
      width: 20,
      height: 20,
      fit: ImageFit.contain,
    );
    final decoded = img.decodePng(out)!;
    // 40x20 scaled to fit 20x20 -> 20x10.
    expect(decoded.width, 20);
    expect(decoded.height, 10);
  });

  test('thumbnail caps the longest edge and keeps aspect ratio', () {
    final out = ImageOps.thumbnail(solid(512, 256), maxSize: 128);
    final decoded = img.decodePng(out)!;
    expect(decoded.width, 128);
    expect(decoded.height, 64);
  });

  test('thumbnail leaves small images untouched in size', () {
    final out = ImageOps.thumbnail(solid(64, 48), maxSize: 256);
    final decoded = img.decodePng(out)!;
    expect(decoded.width, 64);
    expect(decoded.height, 48);
  });

  test('horizontal merge widens the canvas to hold both cells', () {
    final out = ImageOps.merge(
      [solid(30, 30), solid(30, 30)],
      layout: MergeLayout.horizontal,
      gap: 5,
    );
    final decoded = img.decodePng(out)!;
    // 2 cells of 30 + 3 gaps of 5 = 75 wide; 1 row of 30 + 2 gaps = 40 tall.
    expect(decoded.width, 75);
    expect(decoded.height, 40);
  });

  test('compare places two images side by side', () {
    final out = ImageOps.compare(solid(20, 20), solid(20, 20));
    final decoded = img.decodePng(out)!;
    expect(decoded.width > decoded.height, isTrue);
  });

  test('crop returns the requested region clamped to bounds', () {
    final out = ImageOps.crop(solid(100, 80), x: 10, y: 10, width: 40, height: 30);
    final decoded = img.decodePng(out)!;
    expect(decoded.width, 40);
    expect(decoded.height, 30);
  });

  test('crop clamps oversized regions to the image', () {
    final out = ImageOps.crop(solid(50, 50), x: 40, y: 40, width: 100, height: 100);
    final decoded = img.decodePng(out)!;
    expect(decoded.width, 10);
    expect(decoded.height, 10);
  });

  test('annotate returns a same-size image with shapes drawn', () {
    final out = ImageOps.annotate(solid(60, 60), [
      {'type': 'rect', 'x1': 5, 'y1': 5, 'x2': 40, 'y2': 40},
      {'type': 'line', 'x1': 0, 'y1': 0, 'x2': 59, 'y2': 59},
    ]);
    final decoded = img.decodePng(out)!;
    expect(decoded.width, 60);
    expect(decoded.height, 60);
  });
}
