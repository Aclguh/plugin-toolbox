import 'package:flutter/foundation.dart';

import 'dui_expression_evaluator.dart';
import 'dui_scope_context.dart';

export 'dui_expression_evaluator.dart';
export 'dui_scope_context.dart';

/// 动态界面的响应式状态存储，支持全量与细粒度 Key 级别局部刷新
class DuiState extends ChangeNotifier {
  final Map<String, dynamic> _values = {};
  final Map<String, _KeyNotifier> _keyNotifiers = {};

  /// 正则在 UI 构建期被高频命中，静态化避免每次调用重新编译（支持点号语法嵌套解析）
  static final RegExp _interpolatePattern =
      RegExp(r'\{\{state\.([a-zA-Z0-9_\.]+)\}\}');

  static final Listenable _emptyListenable = ChangeNotifier();

  /// 声明式持久化状态键集合（若键发生变动，自动通知外部持久化）
  final Set<String> persistentKeys = {};

  /// 状态持久化通知回调
  void Function(String key, dynamic value)? onPersist;

  /// 安全读取状态值（优先直取，若未命中则支持深层点号导航解析，例如 "user.profile.name" 或 "items.0.title"）
  dynamic get(String key) => getPath(key);

  /// 深层点号语法读取（例如 "user.profile.name" 或 "items.0.title"）
  dynamic getPath(String path) {
    if (_values.containsKey(path)) return _values[path];
    if (!path.contains('.')) return _values[path];

    final segments = path.split('.');
    dynamic current = _values[segments.first];
    for (var i = 1; i < segments.length; i++) {
      if (current == null) return null;
      final seg = segments[i];
      if (current is Map) {
        current = current[seg];
      } else if (current is List) {
        final index = int.tryParse(seg);
        if (index != null && index >= 0 && index < current.length) {
          current = current[index];
        } else {
          return null;
        }
      } else {
        return null;
      }
    }
    return current;
  }

  /// 设置指定键的状态值
  ///
  /// 仅通知监听该键的局部订阅者（精确局部刷新，杜绝无差别全量穿透）；
  /// 若需要显式触发全局监听器（如重置或整体置换），可将 [notifyGlobal] 设为 true。
  void set(String key, dynamic value,
      {bool notifyGlobal = false, bool force = false}) {
    if (force || _values[key] != value || value is List || value is Map) {
      _values[key] = value;
      _keyNotifiers[key]?.notify();
      _notifyPathMatches(key);
      if (notifyGlobal) {
        notifyListeners();
      }
      if (persistentKeys.contains(key)) {
        onPersist?.call(key, value);
      }
    }
  }

  void _notifyPathMatches(String key) {
    for (final entry in _keyNotifiers.entries) {
      if (entry.key != key &&
          (entry.key.startsWith('$key.') || key.startsWith('${entry.key}.'))) {
        entry.value.notify();
      }
    }
  }

  /// 批量设置状态键值
  void setAll(Map<String, dynamic> entries, {bool notifyGlobal = false}) {
    var hasChanged = false;
    for (final entry in entries.entries) {
      if (_values[entry.key] != entry.value) {
        _values[entry.key] = entry.value;
        _keyNotifiers[entry.key]?.notify();
        _notifyPathMatches(entry.key);
        hasChanged = true;
        if (persistentKeys.contains(entry.key)) {
          onPersist?.call(entry.key, entry.value);
        }
      }
    }
    if (hasChanged && notifyGlobal) {
      notifyListeners();
    }
  }

  /// 重置状态存储并通知全部订阅者
  void reset([Map<String, dynamic>? initialValues]) {
    _values.clear();
    if (initialValues != null) {
      _values.addAll(initialValues);
    }
    for (final notifier in _keyNotifiers.values) {
      notifier.notify();
    }
    notifyListeners();
  }

  Map<String, dynamic> getAll() => Map.unmodifiable(_values);

  /// 显式通知特定键的局部监听者（适用于对复杂对象就地修改后的精确刷新）
  void notifyKey(String key) {
    _keyNotifiers[key]?.notify();
    _notifyPathMatches(key);
  }

  /// 获取指定键的局部监听对象（用于针对单一字段的局部精准刷新）
  Listenable listenableForKey(String key) {
    return _keyNotifiers.putIfAbsent(key, () => _KeyNotifier());
  }

  /// 获取一组键的合并局部监听对象
  Listenable listenableForKeys(Iterable<String> keys) {
    final list = keys.map(listenableForKey).toList();
    if (list.isEmpty) return _emptyListenable;
    if (list.length == 1) return list.first;
    return Listenable.merge(list);
  }

  static final RegExp _keyExtractorPattern =
      RegExp(r'(?:\{\{\s*)?state\.([a-zA-Z0-9_\.]+)');

  /// 从模板字符串或条件表达式中提取所有引用的状态键名
  static Set<String> extractKeys(String? template) {
    if (template == null || !template.contains('state.')) return const {};
    final matches = _keyExtractorPattern.allMatches(template);
    final set = <String>{};
    for (final m in matches) {
      final path = m.group(1);
      if (path != null && path.isNotEmpty) {
        set.add(path);
        if (path.contains('.')) {
          set.add(path.split('.').first);
        }
      }
    }
    return set;
  }

  static final RegExp _scopedVarPattern =
      RegExp(r'\{\{\s*(\$(?:index|item(?:\.[a-zA-Z0-9_]+)*))\s*\}\}');

  static final RegExp _bareScopedVarPattern =
      RegExp(r'(?<![a-zA-Z0-9_])(\$(?:index|item(?:\.[a-zA-Z0-9_]+)*))');

  /// 解析包含 {{state.key}} 或 {{state.a.b}} 模板语法的文本（支持可选的作用域环境变量）
  String interpolate(String template, [DuiScopeContext? scope]) {
    var result = template;
    if (scope != null && result.contains(r'$')) {
      result = result.replaceAllMapped(_scopedVarPattern, (m) {
        final varName = m.group(1);
        if (varName != null) {
          final val = scope.resolve(varName);
          return val?.toString() ?? '';
        }
        return '';
      });
    }
    return result.replaceAllMapped(_interpolatePattern, (match) {
      final key = match.group(1);
      if (key == null) return '';
      final val = getPath(key);
      return val?.toString() ?? '';
    });
  }

  /// 计算布尔可见性表达式（支持数值比较、逻辑运算与符合语法，以及可选作用域变量）
  bool evaluateVisible(dynamic expr, [DuiScopeContext? scope]) {
    if (expr == null) return true;
    if (expr is bool) return expr;
    var str = expr.toString().trim();
    if (str.isEmpty) return true;
    if (str == 'true') return true;
    if (str == 'false') return false;

    if (scope != null && str.contains(r'$')) {
      str = str.replaceAllMapped(_scopedVarPattern, (m) {
        final varName = m.group(1);
        if (varName != null) {
          final val = scope.resolve(varName);
          return val?.toString() ?? '';
        }
        return '';
      });
      str = str.replaceAllMapped(_bareScopedVarPattern, (m) {
        final varName = m.group(1);
        if (varName != null) {
          final val = scope.resolve(varName);
          return val?.toString() ?? '';
        }
        return '';
      });
    }

    return DuiExpressionEvaluator.evaluate(str, _values);
  }

  @override
  void dispose() {
    for (final notifier in _keyNotifiers.values) {
      notifier.dispose();
    }
    _keyNotifiers.clear();
    _values.clear();
    super.dispose();
  }
}

class _KeyNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}
