import 'dart:io';

import 'image_ops.dart';
import 'media_asset.dart';

abstract interface class ThumbnailService {
  Future<MediaAsset> createThumbnail({
    required MediaAsset asset,
    required Directory mediaRoot,
  });
}

class PassthroughThumbnailService implements ThumbnailService {
  const PassthroughThumbnailService();

  @override
  Future<MediaAsset> createThumbnail({
    required MediaAsset asset,
    required Directory mediaRoot,
  }) async {
    return asset.copyWith(thumbnailRelativePath: asset.relativePath);
  }
}

/// Generates a real downscaled thumbnail next to the original asset and
/// records its relative path. Falls back to the original path if the source
/// cannot be decoded (e.g. non-image data).
class ImageThumbnailService implements ThumbnailService {
  const ImageThumbnailService({this.maxSize = 256});

  final int maxSize;

  @override
  Future<MediaAsset> createThumbnail({
    required MediaAsset asset,
    required Directory mediaRoot,
  }) async {
    if (!asset.mimeType.startsWith('image/')) {
      return asset.copyWith(thumbnailRelativePath: asset.relativePath);
    }
    try {
      final sep = Platform.pathSeparator;
      final source = File('${mediaRoot.path}$sep${asset.relativePath}');
      final bytes = await source.readAsBytes();
      final thumbBytes = ImageOps.thumbnail(bytes, maxSize: maxSize);

      final thumbRelative = _thumbPathFor(asset.relativePath);
      final thumbFile = File('${mediaRoot.path}$sep$thumbRelative');
      await thumbFile.parent.create(recursive: true);
      await thumbFile.writeAsBytes(thumbBytes, flush: true);

      return asset.copyWith(thumbnailRelativePath: thumbRelative);
    } catch (_) {
      // Non-fatal: fall back to using the original as its own thumbnail.
      return asset.copyWith(thumbnailRelativePath: asset.relativePath);
    }
  }

  String _thumbPathFor(String relativePath) {
    final dot = relativePath.lastIndexOf('.');
    if (dot <= 0) return '$relativePath-thumb.png';
    return '${relativePath.substring(0, dot)}-thumb.png';
  }
}

