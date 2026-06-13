import 'package:mmkv/mmkv.dart';

import 'local_kv_store.dart';

class MmkvLocalKvStore implements LocalKvStore {
  MmkvLocalKvStore({MMKV? mmkv}) : _mmkv = mmkv ?? MMKV.defaultMMKV();

  final MMKV _mmkv;

  @override
  bool containsKey(String key) => _mmkv.containsKey(key);

  @override
  bool getBool(String key, {bool defaultValue = false}) {
    return _mmkv.decodeBool(key, defaultValue: defaultValue);
  }

  @override
  int getInt(String key, {int defaultValue = 0}) {
    return _mmkv.decodeInt(key, defaultValue: defaultValue);
  }

  @override
  String? getString(String key) => _mmkv.decodeString(key);

  @override
  void remove(String key) => _mmkv.removeValue(key);

  @override
  bool setBool(String key, bool value) => _mmkv.encodeBool(key, value);

  @override
  bool setInt(String key, int value) => _mmkv.encodeInt(key, value);

  @override
  bool setString(String key, String value) => _mmkv.encodeString(key, value);
}
