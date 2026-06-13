abstract interface class LocalKvStore {
  String? getString(String key);

  bool setString(String key, String value);

  bool getBool(String key, {bool defaultValue = false});

  bool setBool(String key, bool value);

  int getInt(String key, {int defaultValue = 0});

  bool setInt(String key, int value);

  bool containsKey(String key);

  void remove(String key);
}
