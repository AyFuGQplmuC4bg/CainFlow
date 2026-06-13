import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cain_flow_mob/core/storage/local_kv_store.dart';
import 'package:cain_flow_mob/core/storage/storage_keys.dart';
import 'package:cain_flow_mob/features/media/media_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'stores media bytes as files and indexes metadata in LocalKvStore',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'cain_flow_media_test_',
      );
      addTearDown(() async {
        if (await temp.exists()) await temp.delete(recursive: true);
      });
      final store = _MemoryLocalKvStore();
      final repository = MediaRepository(
        store: store,
        mediaRoot: temp,
        now: () => DateTime.utc(2026, 6, 13, 12),
      );

      final asset = await repository.saveBytes(
        workflowId: 'workflow demo',
        fileName: 'generated image.png',
        mimeType: 'image/png',
        bytes: Uint8List.fromList([1, 2, 3, 4]),
      );

      final file = await repository.fileFor(asset);
      expect(await file.exists(), isTrue);
      expect(await file.readAsBytes(), [1, 2, 3, 4]);
      expect(asset.thumbnailRelativePath, asset.relativePath);

      final rawIndex = store.getString(StorageKeys.mediaAssetIndex)!;
      expect(rawIndex, isNot(contains('1, 2, 3, 4')));
      final decoded = jsonDecode(rawIndex) as List<dynamic>;
      expect(decoded.single['mimeType'], 'image/png');
      expect(decoded.single['relativePath'], asset.relativePath);
      expect(repository.loadForWorkflow('workflow demo').single.id, asset.id);
    },
  );

  test('cleans files and index entries for inactive workflows', () async {
    final temp = await Directory.systemTemp.createTemp('cain_flow_media_test_');
    addTearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });
    final repository = MediaRepository(
      store: _MemoryLocalKvStore(),
      mediaRoot: temp,
      now: () => DateTime.utc(2026, 6, 13, 12),
    );

    final active = await repository.saveBytes(
      workflowId: 'active',
      fileName: 'a.png',
      mimeType: 'image/png',
      bytes: Uint8List.fromList([1]),
    );
    final orphan = await repository.saveBytes(
      workflowId: 'orphan',
      fileName: 'b.png',
      mimeType: 'image/png',
      bytes: Uint8List.fromList([2]),
    );

    final activeFile = await repository.fileFor(active);
    final orphanFile = await repository.fileFor(orphan);
    final removed = await repository.cleanOrphanedAssets(['active']);

    expect(removed, 1);
    expect(await activeFile.exists(), isTrue);
    expect(await orphanFile.exists(), isFalse);
    expect(repository.loadAll().map((asset) => asset.workflowId), ['active']);
  });
}

class _MemoryLocalKvStore implements LocalKvStore {
  final Map<String, Object> _values = {};

  @override
  bool containsKey(String key) => _values.containsKey(key);

  @override
  bool getBool(String key, {bool defaultValue = false}) {
    return _values[key] as bool? ?? defaultValue;
  }

  @override
  int getInt(String key, {int defaultValue = 0}) {
    return _values[key] as int? ?? defaultValue;
  }

  @override
  String? getString(String key) => _values[key] as String?;

  @override
  void remove(String key) {
    _values.remove(key);
  }

  @override
  bool setBool(String key, bool value) {
    _values[key] = value;
    return true;
  }

  @override
  bool setInt(String key, int value) {
    _values[key] = value;
    return true;
  }

  @override
  bool setString(String key, String value) {
    _values[key] = value;
    return true;
  }
}
