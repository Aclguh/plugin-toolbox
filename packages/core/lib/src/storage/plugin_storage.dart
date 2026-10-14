import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

/// 插件沙箱持久化存储抽象接口
abstract class PluginStorage {
  /// 读取字符串值，键不存在时返回 null
  Future<String?> getString(String key);

  /// 写入字符串值
  Future<bool> setString(String key, String value);

  /// 读取布尔值，键不存在时返回 null
  Future<bool?> getBool(String key);

  /// 写入布尔值
  Future<bool> setBool(String key, bool value);

  /// 读取整型值，键不存在时返回 null
  Future<int?> getInt(String key);

  /// 写入整型值
  Future<bool> setInt(String key, int value);

  /// 读取浮点值，键不存在时返回 null
  Future<double?> getDouble(String key);

  /// 写入浮点值
  Future<bool> setDouble(String key, double value);

  /// 读取字符串列表，键不存在时返回 null
  Future<List<String>?> getStringList(String key);

  /// 写入字符串列表
  Future<bool> setStringList(String key, List<String> value);

  /// 移除指定键的值
  Future<bool> remove(String key);

  /// 清除当前插件命名空间下的所有键值
  Future<bool> clear();
}

/// 基于插件沙箱目录内独立 `storage.json` 的文件持久化存储实现。
///
/// 相比共享全局 SharedPreferences：
/// 1. 实现存储物理隔离，各插件存储文件存放在其沙箱根目录下，与沙箱同生共死；
/// 2. 插件卸载或清理沙箱时随目录一并清除，杜绝全局 Key 污染；
/// 3. 支持透明迁移旧版存放在 SharedPreferences 中的遗留数据。
class PluginFileStorageImpl implements PluginStorage {
  final String namespace;
  final Directory rootDir;
  final String fileName;

  PluginFileStorageImpl({
    required this.namespace,
    required this.rootDir,
    this.fileName = 'storage.json',
  });

  File get _file => File('${rootDir.path}/$fileName');
  Map<String, dynamic>? _data;

  Future<void> _ensureLoaded() async {
    if (_data != null) return;
    if (_file.existsSync()) {
      try {
        final content = await _file.readAsString();
        final decoded = jsonDecode(content);
        if (decoded is Map<String, dynamic>) {
          _data = decoded;
          return;
        }
      } catch (_) {}
    }

    _data = <String, dynamic>{};
    // 首次加载且无本地 storage.json 时，尝试平滑迁移 SharedPreferences 遗留数据
    try {
      final prefs = await SharedPreferences.getInstance();
      final prefix = 'plugin.$namespace.';
      final keys = prefs.getKeys().where((k) => k.startsWith(prefix)).toList();
      if (keys.isNotEmpty) {
        for (final k in keys) {
          final stripped = k.substring(prefix.length);
          final val = prefs.get(k);
          if (val != null) {
            _data![stripped] = val;
          }
        }
        await _save();
      }
    } catch (_) {}
  }

  Future<bool> _save() async {
    try {
      if (!rootDir.existsSync()) {
        await rootDir.create(recursive: true);
      }
      final tmpFile = File('${_file.path}.tmp');
      await tmpFile.writeAsString(jsonEncode(_data));
      if (await _file.exists()) {
        await _file.delete();
      }
      await tmpFile.rename(_file.path);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String?> getString(String key) async {
    await _ensureLoaded();
    final val = _data![key];
    return val is String ? val : null;
  }

  @override
  Future<bool> setString(String key, String value) async {
    await _ensureLoaded();
    _data![key] = value;
    return _save();
  }

  @override
  Future<bool?> getBool(String key) async {
    await _ensureLoaded();
    final val = _data![key];
    return val is bool ? val : null;
  }

  @override
  Future<bool> setBool(String key, bool value) async {
    await _ensureLoaded();
    _data![key] = value;
    return _save();
  }

  @override
  Future<int?> getInt(String key) async {
    await _ensureLoaded();
    final val = _data![key];
    if (val is int) return val;
    if (val is num) return val.toInt();
    return null;
  }

  @override
  Future<bool> setInt(String key, int value) async {
    await _ensureLoaded();
    _data![key] = value;
    return _save();
  }

  @override
  Future<double?> getDouble(String key) async {
    await _ensureLoaded();
    final val = _data![key];
    if (val is num) return val.toDouble();
    return null;
  }

  @override
  Future<bool> setDouble(String key, double value) async {
    await _ensureLoaded();
    _data![key] = value;
    return _save();
  }

  @override
  Future<List<String>?> getStringList(String key) async {
    await _ensureLoaded();
    final val = _data![key];
    if (val is List) {
      return val.map((e) => e.toString()).toList();
    }
    return null;
  }

  @override
  Future<bool> setStringList(String key, List<String> value) async {
    await _ensureLoaded();
    _data![key] = value;
    return _save();
  }

  @override
  Future<bool> remove(String key) async {
    await _ensureLoaded();
    if (_data!.containsKey(key)) {
      _data!.remove(key);
      return _save();
    }
    return true;
  }

  @override
  Future<bool> clear() async {
    await _ensureLoaded();
    _data!.clear();
    try {
      if (await _file.exists()) {
        await _file.delete();
      }
    } catch (_) {}

    // 清理可能存在的旧 SharedPreferences 遗留数据
    try {
      final prefs = await SharedPreferences.getInstance();
      final prefix = 'plugin.$namespace.';
      final keys = prefs.getKeys().where((k) => k.startsWith(prefix)).toList();
      for (final k in keys) {
        await prefs.remove(k);
      }
    } catch (_) {}
    return true;
  }
}

class PluginStorageImpl implements PluginStorage {
  final String namespace;

  PluginStorageImpl({required this.namespace});

  String _key(String key) => 'plugin.$namespace.$key';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  @override
  Future<String?> getString(String key) async =>
      (await _prefs).getString(_key(key));

  @override
  Future<bool> setString(String key, String value) async =>
      (await _prefs).setString(_key(key), value);

  @override
  Future<bool?> getBool(String key) async => (await _prefs).getBool(_key(key));

  @override
  Future<bool> setBool(String key, bool value) async =>
      (await _prefs).setBool(_key(key), value);

  @override
  Future<int?> getInt(String key) async => (await _prefs).getInt(_key(key));

  @override
  Future<bool> setInt(String key, int value) async =>
      (await _prefs).setInt(_key(key), value);

  @override
  Future<double?> getDouble(String key) async =>
      (await _prefs).getDouble(_key(key));

  @override
  Future<bool> setDouble(String key, double value) async =>
      (await _prefs).setDouble(_key(key), value);

  @override
  Future<List<String>?> getStringList(String key) async =>
      (await _prefs).getStringList(_key(key));

  @override
  Future<bool> setStringList(String key, List<String> value) async =>
      (await _prefs).setStringList(_key(key), value);

  @override
  Future<bool> remove(String key) async => (await _prefs).remove(_key(key));

  /// 清除该插件命名空间下的所有持久化键值。
  ///
  /// 【性能特征与架构演进说明】
  /// 当前实现针对 SharedPreferences 全局键集合进行 O(N) 前缀过滤并逐项移除。
  /// 在通用移动应用场景下（全局持久化键数通常在数百以内），该操作耗时为毫秒级且仅在卸载/清理时低频调用。
  /// 规划路径：
  /// - 中期：在插件写入时同步维护命名空间内部键索引集合，清理时直接按索引批量删除。
  /// - 长期：随着插件生态丰富，可按需平滑迁移至独立 Box/Collection 隔离的轻量嵌入式存储（如 Hive / Isar）。
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

/// 插件持久化存储工厂，负责按插件 ID 实例化隔离的 [PluginStorage]
class PluginStorageFactory {
  /// 创建存储工厂实例
  const PluginStorageFactory();

  /// 为指定插件 [pluginId] 创建命名空间隔离的持久化存储对象。
  ///
  /// 若提供沙箱根目录 [rootDir]，则使用插件沙箱内的独立 `storage.json` 文件进行持久化存储；
  /// 未提供时回退至共享的 `SharedPreferences` 命名空间存储。
  PluginStorage create(String pluginId, {Directory? rootDir}) {
    if (rootDir != null) {
      return PluginFileStorageImpl(namespace: pluginId, rootDir: rootDir);
    }
    return PluginStorageImpl(namespace: pluginId);
  }
}
