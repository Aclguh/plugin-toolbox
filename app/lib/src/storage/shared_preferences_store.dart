import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 将 Android 宿主平台的 [SharedPreferences] 适配包装为 core 层的 [KeyValueStore] 抽象。
class SharedPreferencesKeyValueStore implements KeyValueStore {
  final SharedPreferences _prefs;

  const SharedPreferencesKeyValueStore(this._prefs);

  @override
  String? getString(String key) => _prefs.getString(key);

  @override
  Future<bool> setString(String key, String value) =>
      _prefs.setString(key, value);

  @override
  bool? getBool(String key) => _prefs.getBool(key);

  @override
  Future<bool> setBool(String key, bool value) => _prefs.setBool(key, value);

  @override
  int? getInt(String key) => _prefs.getInt(key);

  @override
  Future<bool> setInt(String key, int value) => _prefs.setInt(key, value);

  @override
  double? getDouble(String key) => _prefs.getDouble(key);

  @override
  Future<bool> setDouble(String key, double value) =>
      _prefs.setDouble(key, value);

  @override
  List<String>? getStringList(String key) => _prefs.getStringList(key);

  @override
  Future<bool> setStringList(String key, List<String> value) =>
      _prefs.setStringList(key, value);

  @override
  Set<String> getKeys() => _prefs.getKeys();

  @override
  Future<bool> remove(String key) => _prefs.remove(key);

  @override
  Future<bool> clear() => _prefs.clear();
}
