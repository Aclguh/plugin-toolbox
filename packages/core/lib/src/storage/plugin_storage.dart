import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:logger/logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../event/app_event.dart';
import '../event/event_bus.dart';

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

  /// 读取任意支持类型的持久化值
  Future<dynamic> getValue(String key);

  /// 写入任意支持类型的持久化值
  Future<bool> setValue(String key, dynamic value);

  /// 读取持久化值（[getValue] 的便捷别名）
  Future<dynamic> get(String key);

  /// 写入持久化值（[setValue] 的便捷别名）
  Future<bool> set(String key, dynamic value);

  /// 将内存中的脏数据立即同步/落盘至持久化介质
  Future<bool> flush();
}

/// 基于插件沙箱目录内独立 `storage.json` 的文件持久化存储实现。
///
/// 相比共享全局 SharedPreferences：
/// 1. 实现存储物理隔离，各插件存储文件存放在其沙箱根目录下，与沙箱同生共死；
/// 2. 插件卸载或清理沙箱时随目录一并清除，杜绝全局 Key 污染；
/// 3. 支持透明迁移旧版存放在 SharedPreferences 中的遗留数据；
/// 4. 支持 50ms 脏写合并防抖（Debounce），避免连续写入引发频繁磁盘 I/O；
/// 5. 具备异常诊断日志上报与备份恢复告警机制，杜绝数据静默丢失。
class PluginFileStorageImpl implements PluginStorage {
  final String namespace;
  final Directory rootDir;
  final String fileName;
  final Duration debounceDuration;
  final EventBus? eventBus;
  final Logger? logger;

  PluginFileStorageImpl({
    required this.namespace,
    required this.rootDir,
    this.fileName = 'storage.json',
    this.debounceDuration = const Duration(milliseconds: 50),
    this.eventBus,
    this.logger,
  });

  File get _file => File('${rootDir.path}/$fileName');
  Map<String, dynamic>? _data;
  Future<void>? _loadFuture;
  Future<void> _writeQueue = Future.value();
  Timer? _debounceTimer;
  final List<Completer<bool>> _pendingCompleters = [];
  bool _isDirty = false;

  Future<void> _ensureLoaded() {
    return _loadFuture ??= _doLoad();
  }

  Future<void> _doLoad() async {
    if (_data != null) return;
    Object? primaryError;

    if (_file.existsSync()) {
      try {
        final content = await _file.readAsString();
        final decoded = jsonDecode(content);
        if (decoded is Map<String, dynamic>) {
          _data = decoded;
          return;
        }
        primaryError = const FormatException('storage.json 根节点不是 Map 对象');
      } catch (e, st) {
        primaryError = e;
        logger?.w(
          '[$namespace] 主存储文件读取或解析失败: ${_file.path}',
          error: e,
          stackTrace: st,
        );
      }
    }

    final bakFile = File('${_file.path}.bak');
    if (bakFile.existsSync()) {
      try {
        final content = await bakFile.readAsString();
        final decoded = jsonDecode(content);
        if (decoded is Map<String, dynamic>) {
          _data = decoded;
          logger?.i('[$namespace] 成功从备份文件恢复存储数据: ${bakFile.path}');
          eventBus?.fire(StorageCorruptionEvent(
            namespace: namespace,
            filePath: _file.path,
            reason: '主存储文件损坏或格式无效 (${primaryError ?? '未知原因'})，已自动从 .bak 备份恢复',
            recoveredFromBackup: true,
          ));
          return;
        }
      } catch (e, st) {
        logger?.w(
          '[$namespace] 备份文件解析失败: ${bakFile.path}',
          error: e,
          stackTrace: st,
        );
      }
    }

    final tmpFile = File('${_file.path}.tmp');
    if (tmpFile.existsSync()) {
      try {
        final content = await tmpFile.readAsString();
        final decoded = jsonDecode(content);
        if (decoded is Map<String, dynamic>) {
          _data = decoded;
          logger?.i('[$namespace] 成功从未完成写入的临时文件恢复存储数据: ${tmpFile.path}');
          eventBus?.fire(StorageCorruptionEvent(
            namespace: namespace,
            filePath: _file.path,
            reason: '主存储文件与备份均不可用，已尝试从 .tmp 临时文件恢复',
            recoveredFromBackup: true,
          ));
          return;
        }
      } catch (e, st) {
        logger?.w(
          '[$namespace] 临时文件解析失败: ${tmpFile.path}',
          error: e,
          stackTrace: st,
        );
      }
    }

    if (primaryError != null) {
      logger?.e('[$namespace] 存储文件及其全部备份均已损坏，正在重置为空状态: ${_file.path}');
      eventBus?.fire(StorageCorruptionEvent(
        namespace: namespace,
        filePath: _file.path,
        reason: '主存储文件与全部备份损坏且无法恢复 ($primaryError)，已重置为空',
        recoveredFromBackup: false,
      ));
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
        await _save(immediate: true);
      }
    } catch (e, st) {
      logger?.w(
        '[$namespace] 从 SharedPreferences 迁移遗留数据发生异常',
        error: e,
        stackTrace: st,
      );
    }
  }

  Future<bool> _save({bool immediate = false}) {
    _isDirty = true;
    final completer = Completer<bool>();
    _pendingCompleters.add(completer);

    if (immediate || debounceDuration == Duration.zero) {
      _debounceTimer?.cancel();
      _debounceTimer = null;
      _dispatchFlush();
    } else {
      _debounceTimer?.cancel();
      _debounceTimer = Timer(debounceDuration, _dispatchFlush);
    }
    return completer.future;
  }

  void _dispatchFlush() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    if (!_isDirty && _pendingCompleters.isEmpty) return;

    final completers = List<Completer<bool>>.from(_pendingCompleters);
    _pendingCompleters.clear();
    _isDirty = false;

    _writeQueue = _writeQueue.then((_) async {
      final ok = await _doSave();
      for (final c in completers) {
        if (!c.isCompleted) c.complete(ok);
      }
    }).catchError((Object e, StackTrace st) {
      logger?.e('[$namespace] 异步刷盘队列执行失败', error: e, stackTrace: st);
      for (final c in completers) {
        if (!c.isCompleted) c.complete(false);
      }
    });
  }

  @override
  Future<bool> flush() async {
    _dispatchFlush();
    await _writeQueue;
    return true;
  }

  Future<bool> _doSave() async {
    try {
      if (!rootDir.existsSync()) {
        await rootDir.create(recursive: true);
      }
      final tmpFile = File('${_file.path}.tmp');
      final bakFile = File('${_file.path}.bak');
      await tmpFile.writeAsString(jsonEncode(_data), flush: true);

      // 若原主文件存在，先安全备份至 .bak 再覆盖，确保断电或崩溃时零丢数
      if (await _file.exists()) {
        try {
          if (await bakFile.exists()) {
            await bakFile.delete();
          }
          await _file.rename(bakFile.path);
        } catch (_) {}
      }

      await tmpFile.rename(_file.path);
      return true;
    } catch (e, st) {
      logger?.w(
        '[$namespace] 存储文件写入或原子替换失败: ${_file.path}',
        error: e,
        stackTrace: st,
      );
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
  Future<dynamic> getValue(String key) async {
    await _ensureLoaded();
    return _data![key];
  }

  @override
  Future<bool> setValue(String key, dynamic value) async {
    await _ensureLoaded();
    _data![key] = value;
    return _save();
  }

  @override
  Future<dynamic> get(String key) => getValue(key);

  @override
  Future<bool> set(String key, dynamic value) => setValue(key, value);

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
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _isDirty = false;
    for (final c in _pendingCompleters) {
      if (!c.isCompleted) c.complete(false);
    }
    _pendingCompleters.clear();
    await _ensureLoaded();
    _data!.clear();
    try {
      if (await _file.exists()) {
        await _file.delete();
      }
      final bakFile = File('${_file.path}.bak');
      if (await bakFile.exists()) {
        await bakFile.delete();
      }
      final tmpFile = File('${_file.path}.tmp');
      if (await tmpFile.exists()) {
        await tmpFile.delete();
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
  Future<bool> flush() async => true;

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

  @override
  Future<dynamic> getValue(String key) async {
    final prefs = await _prefs;
    return prefs.get(_key(key));
  }

  @override
  Future<bool> setValue(String key, dynamic value) async {
    if (value is String) return setString(key, value);
    if (value is bool) return setBool(key, value);
    if (value is int) return setInt(key, value);
    if (value is double) return setDouble(key, value);
    if (value is List<String>) return setStringList(key, value);
    return setString(key, jsonEncode(value));
  }

  @override
  Future<dynamic> get(String key) => getValue(key);

  @override
  Future<bool> set(String key, dynamic value) => setValue(key, value);

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

/// 插件持久化存储工厂，负责按插件 ID 实例化隔离的 [PluginStorage] 并维护进程内实例池
class PluginStorageFactory {
  final EventBus? eventBus;
  final Logger? logger;

  /// 创建存储工厂实例
  const PluginStorageFactory({this.eventBus, this.logger});

  /// 进程内实例缓存池（key 为 "file:${rootDir.path}" 或 "prefs:$pluginId"）
  static final Map<String, PluginStorage> _instances = {};

  static String _cacheKey(String pluginId, Directory? rootDir) {
    if (rootDir != null) {
      return 'file:${rootDir.path.replaceAll(r'\', '/')}';
    }
    return 'prefs:$pluginId';
  }

  /// 为指定插件 [pluginId] 创建或获取命名空间隔离的持久化存储对象。
  ///
  /// 若提供沙箱根目录 [rootDir]，则使用插件沙箱内的独立 `storage.json` 文件进行持久化存储；
  /// 未提供时回退至共享的 `SharedPreferences` 命名空间存储。
  ///
  /// 【实例池化保障】：同一命名空间及沙箱路径在进程生命周期内共享同一单例实例，
  /// 彻底消除多处创建 Storage 导致的内存 `_data` 脏写覆盖与异步写入竞争。
  PluginStorage create(String pluginId, {Directory? rootDir}) {
    final key = _cacheKey(pluginId, rootDir);
    return _instances.putIfAbsent(key, () {
      if (rootDir != null) {
        return PluginFileStorageImpl(
          namespace: pluginId,
          rootDir: rootDir,
          eventBus: eventBus,
          logger: logger,
        );
      }
      return PluginStorageImpl(namespace: pluginId);
    });
  }

  /// 从实例缓存池中显式注销并清理指定插件的 Storage 实例引用（供插件卸载或注销时调用）
  static Future<void> evict(String pluginId, {Directory? rootDir}) async {
    final key = _cacheKey(pluginId, rootDir);
    final storage = _instances.remove(key);
    if (storage != null) {
      await storage.flush();
    }
  }

  /// 清空所有池化实例缓存（主要供测试重置环境使用）
  static void clearPool() {
    _instances.clear();
  }
}
