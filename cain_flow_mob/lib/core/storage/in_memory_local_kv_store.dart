import 'local_kv_store.dart';

/// In-memory [LocalKvStore] used as a fallback when the native MMKV backend
/// is unavailable (e.g. widget tests, or before native init). Values do not
/// persist across process restarts.
class InMemoryLocalKvStore implements LocalKvStore {
  final Map<String, Object> _values = {};

  @override
  bool containsKey(String key) => _values.containsKey(key);

  @override
  bool getBool(String key, {bool defaultValue = false}) =>
      _values[key] as bool? ?? defaultValue;

  @override
  int getInt(String key, {int defaultValue = 0}) =>
      _values[key] as int? ?? defaultValue;

  @override
  String? getString(String key) => _values[key] as String?;

  @override
  void remove(String key) => _values.remove(key);

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
