import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../../core/storage/local_kv_store.dart';
import '../../core/storage/storage_keys.dart';
import 'media_asset.dart';
import 'thumbnail_service.dart';

class MediaRepository {
  MediaRepository({
    required this.store,
    this.thumbnailService = const ImageThumbnailService(),
    Directory? mediaRoot,
    DateTime Function()? now,
  }) : _mediaRootOverride = mediaRoot,
       _now = now ?? DateTime.now;

  final LocalKvStore store;
  final ThumbnailService thumbnailService;
  final Directory? _mediaRootOverride;
  final DateTime Function() _now;

  Future<MediaAsset> saveBytes({
    required String workflowId,
    required String fileName,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    final root = await _mediaRoot();
    final safeWorkflowId = _safePathSegment(workflowId, fallback: 'default');
    final safeFileName = _safeFileName(fileName);
    final assetId = _newAssetId(workflowId, safeFileName);
    final relativePath = [
      'workflows',
      safeWorkflowId,
      'media',
      '$assetId-$safeFileName',
    ].join(Platform.pathSeparator);
    final file = File('${root.path}${Platform.pathSeparator}$relativePath');
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);

    final asset = MediaAsset(
      id: assetId,
      workflowId: workflowId,
      fileName: safeFileName,
      relativePath: relativePath,
      mimeType: mimeType,
      byteLength: bytes.length,
      createdAt: _now().toUtc(),
    );
    final indexed = await thumbnailService.createThumbnail(
      asset: asset,
      mediaRoot: root,
    );
    _saveIndex([...loadAll(), indexed]);
    return indexed;
  }

  List<MediaAsset> loadAll() {
    final raw = store.getString(StorageKeys.mediaAssetIndex);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((item) => MediaAsset.fromJson(Map<String, dynamic>.from(item)))
          .where((asset) => asset.id.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  List<MediaAsset> loadForWorkflow(String workflowId) {
    return [
      for (final asset in loadAll())
        if (asset.workflowId == workflowId) asset,
    ];
  }

  Future<File> fileFor(MediaAsset asset) async {
    final root = await _mediaRoot();
    return File('${root.path}${Platform.pathSeparator}${asset.relativePath}');
  }

  Future<int> cleanOrphanedAssets(Iterable<String> activeWorkflowIds) async {
    final active = activeWorkflowIds.toSet();
    final root = await _mediaRoot();
    final kept = <MediaAsset>[];
    var removed = 0;

    for (final asset in loadAll()) {
      if (active.contains(asset.workflowId)) {
        kept.add(asset);
        continue;
      }
      await _deleteIfExists(root, asset.relativePath);
      if (asset.thumbnailRelativePath.isNotEmpty &&
          asset.thumbnailRelativePath != asset.relativePath) {
        await _deleteIfExists(root, asset.thumbnailRelativePath);
      }
      removed += 1;
    }

    _saveIndex(kept);
    return removed;
  }

  Future<void> releaseWorkflowMemory(String workflowId) async {
    // Native Flutter image caches are global; this is the explicit repository
    // boundary callers use before closing a workflow or after large imports.
    loadForWorkflow(workflowId);
  }

  Future<Directory> _mediaRoot() async {
    if (_mediaRootOverride != null) {
      await _mediaRootOverride.create(recursive: true);
      return _mediaRootOverride;
    }
    final docs = await getApplicationDocumentsDirectory();
    final root = Directory(
      '${docs.path}${Platform.pathSeparator}CainFlowMedia',
    );
    await root.create(recursive: true);
    return root;
  }

  /// Public accessor for the resolved media root directory.
  Future<Directory> mediaRoot() => _mediaRoot();

  void _saveIndex(List<MediaAsset> assets) {
    store.setString(
      StorageKeys.mediaAssetIndex,
      jsonEncode(assets.map((asset) => asset.toJson()).toList()),
    );
  }

  String _newAssetId(String workflowId, String fileName) {
    final timestamp = _now().toUtc().microsecondsSinceEpoch;
    final seed = _safePathSegment('$workflowId-$fileName', fallback: 'asset');
    return '$timestamp-$seed';
  }
}

Future<void> _deleteIfExists(Directory root, String relativePath) async {
  final file = File('${root.path}${Platform.pathSeparator}$relativePath');
  if (await file.exists()) await file.delete();
}

String _safeFileName(String value) {
  final trimmed = value.trim();
  final fallback = trimmed.isEmpty ? 'asset.bin' : trimmed;
  return fallback
      .replaceAll(RegExp(r'[\\/:*?"<>|]+'), '_')
      .replaceAll(RegExp(r'\s+'), '_');
}

String _safePathSegment(String value, {required String fallback}) {
  final sanitized = value
      .trim()
      .replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return sanitized.isEmpty ? fallback : sanitized;
}
