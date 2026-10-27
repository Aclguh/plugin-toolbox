import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:logger/logger.dart';

import '../event/app_event.dart';
import '../event/event_bus.dart';
import 'key_value_store.dart';

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
  final KeyValueStore? legacyStore;

  PluginFileStorageImpl({
    required this.namespace,
    required this.rootDir,
    this.fileName = 'storage.json',
    this.debounceDuration = const Duration(milliseconds: 50),
    this.eventBus,
    this.logger,
    this.legacyStore,
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
    // 首次加载且无本地 storage.json 时，若提供了 legacyStore，尝试平滑迁移遗留数据
    if (legacyStore != null) {
      try {
        final prefix = 'plugin.$namespace.';
        final legacyKeys =
            legacyStore!.getKeys().where((k) => k.startsWith(prefix)).toList();
        if (legacyKeys.isNotEmpty) {
          for (final k in legacyKeys) {
            final stripped = k.substring(prefix.length);
            final val = legacyStore!.getString(k) ??
                legacyStore!.getBool(k) ??
                legacyStore!.getInt(k) ??
                legacyStore!.getDouble(k) ??
                legacyStore!.getStringList(k);
            if (val != null) {
              _data![stripped] = val;
            }
          }
          await _save(immediate: true);
        }
      } catch (e, st) {
        logger?.w(
          '[$namespace] 从遗留 KeyValueStore 迁移数据发生异常',
          error: e,
          stackTrace: st,
        );
      }
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

    // 清理可能存在的旧遗留数据
    if (legacyStore != null) {
      try {
        final prefix = 'plugin.$namespace.';
        final keys =
            legacyStore!.getKeys().where((k) => k.startsWith(prefix)).toList();
        for (final k in keys) {
          await legacyStore!.remove(k);
        }
      } catch (_) {}
    }
    return true;
  }
}

class PluginStorageImpl implements PluginStorage {
  final String namespace;
  final KeyValueStore _store;

  PluginStorageImpl({required this.namespace, KeyValueStore? store})
      : _store = store ?? MemoryKeyValueStore();

  String _key(String key) => 'plugin.$namespace.$key';

  @override
  Future<bool> flush() async => true;

  @override
  Future<String?> getString(String key) async => _store.getString(_key(key));

  @override
  Future<bool> setString(String key, String value) =>
      _store.setString(_key(key), value);

  @override
  Future<bool?> getBool(String key) async => _store.getBool(_key(key));

  @override
  Future<bool> setBool(String key, bool value) =>
      _store.setBool(_key(key), value);

  @override
  Future<int?> getInt(String key) async => _store.getInt(_key(key));

  @override
  Future<bool> setInt(String key, int value) => _store.setInt(_key(key), value);

  @override
  Future<double?> getDouble(String key) async => _store.getDouble(_key(key));

  @override
  Future<bool> setDouble(String key, double value) =>
      _store.setDouble(_key(key), value);

  @override
  Future<List<String>?> getStringList(String key) async =>
      _store.getStringList(_key(key));

  @override
  Future<bool> setStringList(String key, List<String> value) =>
      _store.setStringList(_key(key), value);

  @override
  Future<bool> remove(String key) => _store.remove(_key(key));

  @override
  Future<dynamic> getValue(String key) async {
    final k = _key(key);
    final s = _store.getString(k);
    if (s != null) {
      try {
        return jsonDecode(s);
      } catch (_) {
        return s;
      }
    }
    return _store.getBool(k) ??
        _store.getInt(k) ??
        _store.getDouble(k) ??
        _store.getStringList(k);
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
  @override
  Future<bool> clear() async {
    final prefix = 'plugin.$namespace.';
    final keys = _store.getKeys().where((k) => k.startsWith(prefix)).toList();
    for (final k in keys) {
      await _store.remove(k);
    }
    return true;
  }
}

/// 插件持久化存储工厂，负责按插件 ID 实例化隔离的 [PluginStorage] 并维护进程内实例池
class PluginStorageFactory {
  final EventBus? eventBus;
  final Logger? logger;
  final KeyValueStore? defaultStore;

  /// 创建存储工厂实例
  const PluginStorageFactory({
    this.eventBus,
    this.logger,
    this.defaultStore,
  });

  /// 默认共享内存键值存储实例，用于未提供 defaultStore 时的进程内全局兜底
  static final KeyValueStore _sharedMemoryStore = MemoryKeyValueStore();

  KeyValueStore get _effectiveStore => defaultStore ?? _sharedMemoryStore;

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
  /// 未提供时回退至基于 [defaultStore] 的命名空间存储。
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
          legacyStore: _effectiveStore,
        );
      }
      return PluginStorageImpl(
        namespace: pluginId,
        store: _effectiveStore,
      );
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
    _sharedMemoryStore.clear();
  }
}
