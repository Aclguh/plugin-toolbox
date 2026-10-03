import 'package:shared_preferences/shared_preferences.dart';

abstract class PluginStorage {
  Future<String?> getString(String key);
  Future<bool> setString(String key, String value);
  Future<bool?> getBool(String key);
  Future<bool> setBool(String key, bool value);
  Future<int?> getInt(String key);
  Future<bool> setInt(String key, int value);
  Future<double?> getDouble(String key);
  Future<bool> setDouble(String key, double value);
  Future<List<String>?> getStringList(String key);
  Future<bool> setStringList(String key, List<String> value);
  Future<bool> remove(String key);
  Future<bool> clear();
}

class PluginStorageImpl implements PluginStorage {
  final String namespace;

  PluginStorageImpl({required this.namespace});

  String _key(String key) => 'plugin.$namespace.$key';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  @override
  Future<String?> getString(String key) async => (await _prefs).getString(_key(key));

  @override
  Future<bool> setString(String key, String value) async => (await _prefs).setString(_key(key), value);

  @override
  Future<bool?> getBool(String key) async => (await _prefs).getBool(_key(key));

  @override
  Future<bool> setBool(String key, bool value) async => (await _prefs).setBool(_key(key), value);

  @override
  Future<int?> getInt(String key) async => (await _prefs).getInt(_key(key));

  @override
  Future<bool> setInt(String key, int value) async => (await _prefs).setInt(_key(key), value);

  @override
  Future<double?> getDouble(String key) async => (await _prefs).getDouble(_key(key));

  @override
  Future<bool> setDouble(String key, double value) async => (await _prefs).setDouble(_key(key), value);

  @override
  Future<List<String>?> getStringList(String key) async => (await _prefs).getStringList(_key(key));

  @override
  Future<bool> setStringList(String key, List<String> value) async => (await _prefs).setStringList(_key(key), value);

  @override
  Future<bool> remove(String key) async => (await _prefs).remove(_key(key));

  @override
  Future<bool> clear() async {
    final prefs = await _prefs;
    final prefix = 'plugin.$namespace.';
    final keys = prefs.getKeys().where((k) => k.startsWith(prefix)).toList();
    for (final k in keys) {
      await prefs.remove(k);
    }
    return true;
  }
}

class PluginStorageFactory {
  const PluginStorageFactory();
  PluginStorage create(String pluginId) => PluginStorageImpl(namespace: pluginId);
}
