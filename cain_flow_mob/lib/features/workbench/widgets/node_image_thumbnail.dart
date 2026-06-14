import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../image_preview_screen.dart';

/// Renders a small preview of an image payload (`{kind: url|asset, ...}`)
/// produced by execution. URL payloads stream via [CachedNetworkImage];
/// asset payloads resolve a local file under the media root. Tapping opens a
/// full-screen, pinch-zoomable preview.
class NodeImageThumbnail extends StatelessWidget {
  const NodeImageThumbnail({super.key, required this.payload, this.size = 64});

  final Map<String, dynamic> payload;
  final double size;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _openFullPreview(context),
      child: _buildThumb(context),
    );
  }

  Future<void> _openFullPreview(BuildContext context) async {
    final provider = await imageProviderForPayload(
      payload,
      resolveAsset: _resolveAssetFile,
    );
    if (provider == null || !context.mounted) return;
    await ImagePreviewScreen.open(context, imageProvider: provider);
  }

  Widget _buildThumb(BuildContext context) {
    final kind = payload['kind']?.toString();

    if (kind == 'url') {
      final url = payload['url']?.toString() ?? '';
      if (url.isEmpty) return _placeholder(context);
      return _box(
        CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.cover,
          placeholder: (context, url) => _loading(),
          errorWidget: (context, url, error) => _error(context),
        ),
      );
    }

    if (kind == 'asset') {
      // Prefer the generated thumbnail; fall back to the full asset.
      final relativePath = (payload['thumbnailRelativePath']?.toString() ?? '')
              .isNotEmpty
          ? payload['thumbnailRelativePath'].toString()
          : payload['relativePath']?.toString() ?? '';
      if (relativePath.isEmpty) return _placeholder(context);
      return _box(
        FutureBuilder<File?>(
          future: _resolveAssetFile(relativePath),
          builder: (context, snapshot) {
            final file = snapshot.data;
            if (file == null) return _loading();
            return Image.file(
              file,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stack) => _error(context),
            );
          },
        ),
      );
    }

    return _placeholder(context);
  }

  Widget _box(Widget child) => ClipRRect(
    borderRadius: BorderRadius.circular(6),
    child: SizedBox(width: size, height: size, child: child),
  );

  Widget _loading() => const Center(
    child: SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(strokeWidth: 2),
    ),
  );

  Widget _error(BuildContext context) => Icon(
    Icons.broken_image_outlined,
    color: Theme.of(context).colorScheme.error,
    size: 24,
  );

  Widget _placeholder(BuildContext context) => Icon(
    Icons.image_outlined,
    color: Theme.of(context).colorScheme.onSurfaceVariant,
    size: 24,
  );
}

Future<File?> _resolveAssetFile(String relativePath) async {
  try {
    final docs = await getApplicationDocumentsDirectory();
    final file = File(
      '${docs.path}${Platform.pathSeparator}CainFlowMedia'
      '${Platform.pathSeparator}$relativePath',
    );
    return await file.exists() ? file : null;
  } catch (_) {
    return null;
  }
}
