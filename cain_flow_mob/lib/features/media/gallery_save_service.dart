import 'dart:io';

import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';

import 'media_downloader.dart';

enum GallerySaveStatus {
  saved,
  permissionDenied,
  missingFile,
  unsupportedSource,
  failed,
}

class GallerySaveResult {
  const GallerySaveResult(this.status, {this.message = ''});

  final GallerySaveStatus status;
  final String message;

  bool get isSaved => status == GallerySaveStatus.saved;
}

class GallerySaveService {
  GallerySaveService({
    MediaDownloader? downloader,
    Future<File?> Function(String relativePath)? resolveAsset,
  }) : downloader = downloader ?? MediaDownloader(),
       _resolveAsset = resolveAsset ?? _defaultResolveAsset;

  final MediaDownloader downloader;
  final Future<File?> Function(String relativePath) _resolveAsset;

  Future<GallerySaveResult> saveImagePayload(
    Map<String, dynamic> payload,
  ) async {
    final kind = payload['kind']?.toString();
    if (kind == 'images') {
      final items = payload['items'];
      if (items is List && items.isNotEmpty && items.last is Map) {
        return saveImagePayload(Map<String, dynamic>.from(items.last as Map));
      }
      return const GallerySaveResult(GallerySaveStatus.unsupportedSource);
    }

    final access = await Gal.requestAccess();
    if (!access) {
      return const GallerySaveResult(GallerySaveStatus.permissionDenied);
    }

    try {
      if (kind == 'asset') {
        final relativePath = payload['relativePath']?.toString() ?? '';
        if (relativePath.isEmpty) {
          return const GallerySaveResult(GallerySaveStatus.unsupportedSource);
        }
        final file = await _resolveAsset(relativePath);
        if (file == null || !await file.exists()) {
          return const GallerySaveResult(GallerySaveStatus.missingFile);
        }
        await Gal.putImage(file.path);
        return const GallerySaveResult(GallerySaveStatus.saved);
      }

      if (kind == 'url') {
        final url = payload['url']?.toString() ?? '';
        if (url.isEmpty) {
          return const GallerySaveResult(GallerySaveStatus.unsupportedSource);
        }
        final media = await downloader.download(url);
        await Gal.putImageBytes(
          media.bytes,
          name: 'cainflow_${DateTime.now().microsecondsSinceEpoch}',
        );
        return const GallerySaveResult(GallerySaveStatus.saved);
      }

      return const GallerySaveResult(GallerySaveStatus.unsupportedSource);
    } on GalException catch (error) {
      return GallerySaveResult(switch (error.type) {
        GalExceptionType.accessDenied => GallerySaveStatus.permissionDenied,
        _ => GallerySaveStatus.failed,
      }, message: error.type.message);
    } catch (error) {
      return GallerySaveResult(
        GallerySaveStatus.failed,
        message: error.toString(),
      );
    }
  }
}

Future<File?> _defaultResolveAsset(String relativePath) async {
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
