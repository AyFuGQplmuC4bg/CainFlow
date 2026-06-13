import 'dart:io';

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
