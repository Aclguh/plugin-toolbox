import 'dart:async';

/// 轻量键值存储抽象契约接口。
///
/// 消除领域核心层 (`packages/core`) 对特定平台或框架持久化库（如 `shared_preferences`）的直接强绑定，
/// 允许在纯 Dart CLI、服务器、隔离线程 (Isolates) 或 Flutter 宿主环境中自由注入实现。
abstract class KeyValueStore {
  /// 读取字符串值
  String? getString(String key);

  /// 写入字符串值
  Future<bool> setString(String key, String value);

  /// 读取布尔值
  bool? getBool(String key);

  /// 写入布尔值
  Future<bool> setBool(String key, bool value);

  /// 读取整型值
  int? getInt(String key);

  /// 写入整型值
  Future<bool> setInt(String key, int value);

  /// 读取浮点数值
  double? getDouble(String key);

  /// 写入浮点数值
  Future<bool> setDouble(String key, double value);

  /// 读取字符串列表
  List<String>? getStringList(String key);

  /// 写入字符串列表
  Future<bool> setStringList(String key, List<String> value);

  /// 获取所有已持久化的键集合
  Set<String> getKeys();

  /// 移除指定键
  Future<bool> remove(String key);

  /// 清空所有键值
  Future<bool> clear();
}

/// 纯内存实现的键值存储。
///
/// 默认提供线程安全、非持久化的内存字典存储，主要用于纯 Dart 测试环境、无盘环境或作为离线内存回退缓存。
class MemoryKeyValueStore implements KeyValueStore {
  final Map<String, dynamic> _data = {};

  /// 支持传入初始字典数据
  MemoryKeyValueStore([Map<String, dynamic>? initialData]) {
    if (initialData != null) {
      _data.addAll(initialData);
    }
  }

  @override
  String? getString(String key) {
    final val = _data[key];
    return val is String ? val : null;
  }

  @override
  Future<bool> setString(String key, String value) async {
    _data[key] = value;
    return true;
  }

  @override
  bool? getBool(String key) {
    final val = _data[key];
    return val is bool ? val : null;
  }

  @override
  Future<bool> setBool(String key, bool value) async {
    _data[key] = value;
    return true;
  }

  @override
  int? getInt(String key) {
    final val = _data[key];
    return val is int ? val : null;
  }

  @override
  Future<bool> setInt(String key, int value) async {
    _data[key] = value;
    return true;
  }

  @override
  double? getDouble(String key) {
    final val = _data[key];
    return val is double ? val : null;
  }

  @override
  Future<bool> setDouble(String key, double value) async {
    _data[key] = value;
    return true;
  }

  @override
  List<String>? getStringList(String key) {
    final val = _data[key];
    if (val is List) {
      return val.map((e) => e.toString()).toList();
    }
    return null;
  }

  @override
  Future<bool> setStringList(String key, List<String> value) async {
    _data[key] = List<String>.from(value);
    return true;
  }

  @override
  Set<String> getKeys() => Set<String>.from(_data.keys);

  @override
  Future<bool> remove(String key) async {
    _data.remove(key);
    return true;
  }

  @override
  Future<bool> clear() async {
    _data.clear();
    return true;
  }
}
