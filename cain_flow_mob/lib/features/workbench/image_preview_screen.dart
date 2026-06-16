import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';

import '../media/gallery_save_service.dart';

/// Full-screen, pinch-zoomable preview of an image payload
/// (`{kind: url|asset, ...}`). Opened by tapping a node thumbnail.
class ImagePreviewScreen extends StatelessWidget {
  const ImagePreviewScreen({
    super.key,
    required this.imageProvider,
    this.sourcePayload,
    this.onSaveRequested,
  });

  final ImageProvider imageProvider;
  final Map<String, dynamic>? sourcePayload;
  final Future<GallerySaveResult> Function()? onSaveRequested;

  /// Builds a preview route for a payload, or null if it can't be resolved.
  static Future<void> open(
    BuildContext context, {
    required ImageProvider imageProvider,
    Map<String, dynamic>? sourcePayload,
    Future<GallerySaveResult> Function()? onSaveRequested,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ImagePreviewScreen(
          imageProvider: imageProvider,
          sourcePayload: sourcePayload,
          onSaveRequested: onSaveRequested,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (sourcePayload != null)
            IconButton(
              tooltip: 'Save to gallery',
              onPressed: () async {
                final handler = onSaveRequested;
                if (handler == null) return;
                final messenger = ScaffoldMessenger.of(context);
                final result = await handler();
                if (!context.mounted) return;
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      switch (result.status) {
                        GallerySaveStatus.saved => 'Saved to gallery',
                        GallerySaveStatus.permissionDenied =>
                          'Gallery access denied',
                        GallerySaveStatus.missingFile => 'File not found',
                        GallerySaveStatus.unsupportedSource =>
                          'This image cannot be saved',
                        GallerySaveStatus.failed =>
                          result.message.isEmpty
                              ? 'Save failed'
                              : result.message,
                      },
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.download_rounded),
            ),
        ],
      ),
      body: ExtendedImage(
        image: imageProvider,
        fit: BoxFit.contain,
        mode: ExtendedImageMode.gesture,
        enableLoadState: true,
        initGestureConfigHandler: (_) => GestureConfig(
          minScale: 1,
          maxScale: 4,
          animationMinScale: 0.8,
          animationMaxScale: 4.5,
        ),
        loadStateChanged: (state) {
          if (state.extendedImageLoadState == LoadState.failed) {
            return const Center(
              child: Icon(
                Icons.broken_image_outlined,
                color: Colors.white54,
                size: 48,
              ),
            );
          }
          return null;
        },
      ),
    );
  }
}

/// Resolves an image payload into an [ImageProvider] for full-size preview
/// (prefers the full asset, not the thumbnail). Returns null if unresolvable.
Future<ImageProvider?> imageProviderForPayload(
  Map<String, dynamic> payload, {
  required Future<File?> Function(String relativePath) resolveAsset,
}) async {
  final kind = payload['kind']?.toString();
  if (kind == 'images') {
    final items = payload['items'];
    if (items is List && items.isNotEmpty && items.last is Map) {
      return imageProviderForPayload(
        Map<String, dynamic>.from(items.last as Map),
        resolveAsset: resolveAsset,
      );
    }
    return null;
  }
  if (kind == 'url') {
    final url = payload['url']?.toString() ?? '';
    if (url.isEmpty) return null;
    return CachedNetworkImageProvider(url);
  }
  if (kind == 'asset') {
    final relativePath = payload['relativePath']?.toString() ?? '';
    if (relativePath.isEmpty) return null;
    final file = await resolveAsset(relativePath);
    if (file == null) return null;
    return FileImage(file);
  }
  return null;
}
