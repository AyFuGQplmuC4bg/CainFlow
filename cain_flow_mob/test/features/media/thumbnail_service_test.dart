import 'dart:io';
import 'dart:typed_data';

import 'package:cain_flow_mob/features/media/media_asset.dart';
import 'package:cain_flow_mob/features/media/thumbnail_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('cainflow_thumb_test');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  MediaAsset writeAsset(int w, int h) {
    const relative = 'workflows/wf/media/a1-pic.png';
    final file = File('${root.path}${Platform.pathSeparator}$relative');
    file.parent.createSync(recursive: true);
    final bytes = Uint8List.fromList(
      img.encodePng(img.Image(width: w, height: h)..clear(img.ColorRgb8(0, 128, 255))),
    );
    file.writeAsBytesSync(bytes);
    return MediaAsset(
      id: 'a1',
      workflowId: 'wf',
      fileName: 'pic.png',
      relativePath: relative,
      mimeType: 'image/png',
      byteLength: bytes.length,
      createdAt: DateTime.utc(2026, 1, 1),
    );
  }

  test('generates a downscaled thumbnail file and records its path', () async {
    const service = ImageThumbnailService(maxSize: 64);
    final asset = writeAsset(256, 128);

    final result = await service.createThumbnail(asset: asset, mediaRoot: root);

    expect(result.thumbnailRelativePath, isNot(asset.relativePath));
    expect(result.thumbnailRelativePath, endsWith('-thumb.png'));
    final thumbFile = File(
      '${root.path}${Platform.pathSeparator}${result.thumbnailRelativePath}',
    );
    expect(thumbFile.existsSync(), isTrue);
    final decoded = img.decodePng(thumbFile.readAsBytesSync())!;
    expect(decoded.width, 64);
    expect(decoded.height, 32);
  });

  test('falls back to the original path for non-image assets', () async {
    const service = ImageThumbnailService();
    final asset = MediaAsset(
      id: 'v1',
      workflowId: 'wf',
      fileName: 'clip.mp4',
      relativePath: 'workflows/wf/media/v1-clip.mp4',
      mimeType: 'video/mp4',
      byteLength: 10,
      createdAt: DateTime.utc(2026, 1, 1),
    );

    final result = await service.createThumbnail(asset: asset, mediaRoot: root);
    expect(result.thumbnailRelativePath, asset.relativePath);
  });
}
