import 'package:flutter/foundation.dart';

/// 动态界面的响应式状态存储，支持全量与细粒度 Key 级别局部刷新
class DuiState extends ChangeNotifier {
  final Map<String, dynamic> _values = {};
  final Map<String, _KeyNotifier> _keyNotifiers = {};

  /// 正则在 UI 构建期被高频命中，静态化避免每次调用重新编译
  static final RegExp _interpolatePattern =
      RegExp(r'\{\{state\.([a-zA-Z0-9_]+)\}\}');
  static final RegExp _visibleExprPattern =
      RegExp(r'^\{\{state\.([a-zA-Z0-9_]+)\}\}$');

  dynamic get(String key) => _values[key];

  void set(String key, dynamic value) {
    if (_values[key] != value) {
      _values[key] = value;
      _keyNotifiers[key]?.notify();
      notifyListeners();
    }
  }

  Map<String, dynamic> getAll() => Map.unmodifiable(_values);

  /// 获取指定键的局部监听对象（用于针对单一字段的局部精准刷新）
  Listenable listenableForKey(String key) {
    return _keyNotifiers.putIfAbsent(key, () => _KeyNotifier());
  }

  /// 获取一组键的合并局部监听对象
  Listenable listenableForKeys(Iterable<String> keys) {
    final list = keys.map(listenableForKey).toList();
    if (list.isEmpty) return this;
    if (list.length == 1) return list.first;
    return Listenable.merge(list);
  }

  /// 从模板字符串中提取所有引用的状态键名
  static Set<String> extractKeys(String? template) {
    if (template == null || !template.contains('{{state.')) return const {};
    final matches = _interpolatePattern.allMatches(template);
    final set = <String>{};
    for (final m in matches) {
      final key = m.group(1);
      if (key != null) set.add(key);
    }
    return set;
  }

  /// 解析包含 {{state.key}} 模板语法的文本
  String interpolate(String template) {
    return template.replaceAllMapped(_interpolatePattern, (match) {
      final key = match.group(1);
      if (key == null) return '';
      final val = _values[key];
      return val?.toString() ?? '';
    });
  }

  /// 计算布尔可见性表达式
  bool evaluateVisible(dynamic expr) {
    if (expr == null) return true;
    if (expr is bool) return expr;
    final str = expr.toString().trim();
    if (str.isEmpty) return true;
    if (str == 'true') return true;
    if (str == 'false') return false;

    // 解析形如 "{{state.hasError}}"
    final match = _visibleExprPattern.firstMatch(str);
    if (match != null) {
      final key = match.group(1)!;
      final val = _values[key];
      if (val is bool) return val;
      if (val is String) return val.isNotEmpty;
      if (val is num) return val != 0;
      return val != null;
    }
    return true;
  }

  @override
  void dispose() {
    for (final notifier in _keyNotifiers.values) {
      notifier.dispose();
    }
    _keyNotifiers.clear();
    super.dispose();
  }
}

class _KeyNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}
