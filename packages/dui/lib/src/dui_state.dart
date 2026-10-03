import 'package:flutter/foundation.dart';

/// 动态界面的响应式状态存储
class DuiState extends ChangeNotifier {
  final Map<String, dynamic> _values = {};

  /// 正则在 UI 构建期被高频命中，静态化避免每次调用重新编译
  static final RegExp _interpolatePattern =
      RegExp(r'\{\{state\.([a-zA-Z0-9_]+)\}\}');
  static final RegExp _visibleExprPattern =
      RegExp(r'^\{\{state\.([a-zA-Z0-9_]+)\}\}$');

  dynamic get(String key) => _values[key];

  void set(String key, dynamic value) {
    if (_values[key] != value) {
      _values[key] = value;
      notifyListeners();
    }
  }

  Map<String, dynamic> getAll() => Map.unmodifiable(_values);

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
}
