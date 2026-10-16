import 'package:flutter/foundation.dart';

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
  void set(String key, dynamic value, {bool notifyGlobal = false}) {
    if (_values[key] != value) {
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
    super.dispose();
  }
}

class _KeyNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}

/// 轻量条件表达式解析与计算器，支持数值比较、逻辑复合与类型推导
class DuiExpressionEvaluator {
  static bool evaluate(String rawExpr, Map<String, dynamic> stateValues) {
    var expr = rawExpr.trim();
    if (expr.isEmpty) return true;
    if (expr == 'true') return true;
    if (expr == 'false') return false;

    // 剥离可能包裹的顶层大括号 {{ ... }}
    if (expr.startsWith('{{') && expr.endsWith('}}')) {
      expr = expr.substring(2, expr.length - 2).trim();
    }
    if (expr.isEmpty) return true;

    try {
      return _evalOr(expr, stateValues);
    } catch (_) {
      return true;
    }
  }

  static bool _evalOr(String expr, Map<String, dynamic> values) {
    final parts = _splitTopLevel(expr, '||');
    if (parts.length > 1) {
      for (final part in parts) {
        if (_evalAnd(part, values)) return true;
      }
      return false;
    }
    return _evalAnd(expr, values);
  }

  static bool _evalAnd(String expr, Map<String, dynamic> values) {
    final parts = _splitTopLevel(expr, '&&');
    if (parts.length > 1) {
      for (final part in parts) {
        if (!_evalComparison(part, values)) return false;
      }
      return true;
    }
    return _evalComparison(expr, values);
  }

  static bool _evalComparison(String rawExpr, Map<String, dynamic> values) {
    final expr = rawExpr.trim();
    if (expr.isEmpty) return true;

    if (expr.startsWith('!') && !expr.startsWith('!=')) {
      final inner = expr.substring(1).trim();
      return !_evalComparison(inner, values);
    }

    const ops = ['==', '!=', '>=', '<=', '>', '<'];
    for (final op in ops) {
      final idx = _indexOfOp(expr, op);
      if (idx != -1) {
        final leftStr = expr.substring(0, idx).trim();
        final rightStr = expr.substring(idx + op.length).trim();
        final leftVal = _evalOperand(leftStr, values);
        final rightVal = _evalOperand(rightStr, values);
        return _compare(leftVal, rightVal, op);
      }
    }

    final val = _evalOperand(expr, values);
    return _isTruthy(val);
  }

  static dynamic _evalOperand(String raw, Map<String, dynamic> values) {
    var s = raw.trim();
    if (s.startsWith('{{') && s.endsWith('}}')) {
      s = s.substring(2, s.length - 2).trim();
    }
    if (s.isEmpty) return null;

    // 字符串字面量: '...' 或 "..."
    if ((s.startsWith("'") && s.endsWith("'") && s.length >= 2) ||
        (s.startsWith('"') && s.endsWith('"') && s.length >= 2)) {
      return s.substring(1, s.length - 1);
    }

    // 布尔与空
    if (s == 'true') return true;
    if (s == 'false') return false;
    if (s == 'null') return null;

    // 数字
    final numVal = num.tryParse(s);
    if (numVal != null) return numVal;

    // 状态变量引用: state.key 或 key
    if (s.startsWith('state.')) {
      final key = s.substring(6).trim();
      return _resolvePath(key, values);
    }
    if (values.containsKey(s)) {
      return values[s];
    }
    if (s.contains('.')) {
      final res = _resolvePath(s, values);
      if (res != null) return res;
    }

    return s;
  }

  static dynamic _resolvePath(String path, Map<String, dynamic> values) {
    if (values.containsKey(path)) return values[path];
    if (!path.contains('.')) return values[path];
    final segments = path.split('.');
    dynamic current = values[segments.first];
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

  static bool _compare(dynamic left, dynamic right, String op) {
    if (op == '==') {
      if (left == right) return true;
      if (left is num && right is num) return left == right;
      return left?.toString() == right?.toString();
    }
    if (op == '!=') {
      return !_compare(left, right, '==');
    }

    final leftNum = (left is num) ? left : num.tryParse(left?.toString() ?? '');
    final rightNum =
        (right is num) ? right : num.tryParse(right?.toString() ?? '');

    if (leftNum != null && rightNum != null) {
      switch (op) {
        case '>':
          return leftNum > rightNum;
        case '<':
          return leftNum < rightNum;
        case '>=':
          return leftNum >= rightNum;
        case '<=':
          return leftNum <= rightNum;
      }
    }

    final leftStr = left?.toString() ?? '';
    final rightStr = right?.toString() ?? '';
    final cmp = leftStr.compareTo(rightStr);
    switch (op) {
      case '>':
        return cmp > 0;
      case '<':
        return cmp < 0;
      case '>=':
        return cmp >= 0;
      case '<=':
        return cmp <= 0;
    }
    return false;
  }

  static bool _isTruthy(dynamic val) {
    if (val == null) return false;
    if (val is bool) return val;
    if (val is num) return val != 0;
    if (val is String) return val.isNotEmpty && val != 'false' && val != '0';
    return true;
  }

  static int _indexOfOp(String expr, String op) {
    var inSingle = false;
    var inDouble = false;
    for (var i = 0; i <= expr.length - op.length; i++) {
      final c = expr[i];
      if (c == "'" && !inDouble) {
        inSingle = !inSingle;
      } else if (c == '"' && !inSingle) {
        inDouble = !inDouble;
      } else if (!inSingle && !inDouble) {
        if (expr.substring(i, i + op.length) == op) {
          if (op == '>' && i + 1 < expr.length && expr[i + 1] == '=') continue;
          if (op == '<' && i + 1 < expr.length && expr[i + 1] == '=') continue;
          if (op == '!' && i + 1 < expr.length && expr[i + 1] == '=') continue;
          return i;
        }
      }
    }
    return -1;
  }

  static List<String> _splitTopLevel(String expr, String delimiter) {
    final result = <String>[];
    var inSingle = false;
    var inDouble = false;
    var lastIdx = 0;
    final dLen = delimiter.length;

    for (var i = 0; i <= expr.length - dLen; i++) {
      final c = expr[i];
      if (c == "'" && !inDouble) {
        inSingle = !inSingle;
      } else if (c == '"' && !inSingle) {
        inDouble = !inDouble;
      } else if (!inSingle && !inDouble) {
        if (expr.substring(i, i + dLen) == delimiter) {
          result.add(expr.substring(lastIdx, i).trim());
          lastIdx = i + dLen;
          i += dLen - 1;
        }
      }
    }
    result.add(expr.substring(lastIdx).trim());
    return result;
  }
}

/// 列表项等子树局部作用域环境，封装 $item 与 $index，支持嵌套继承与深度点号解析
class DuiScopeContext {
  final dynamic item;
  final int index;
  final DuiScopeContext? parent;

  const DuiScopeContext({
    required this.item,
    required this.index,
    this.parent,
  });

  /// 解析 $index 或 $item / $item.prop / $item.0
  dynamic resolve(String path) {
    final trimmed = path.trim();
    if (trimmed == r'$index') {
      return index;
    }
    if (trimmed == r'$item') {
      return item;
    }
    if (trimmed.startsWith(r'$item.')) {
      final subPath = trimmed.substring(6);
      return _resolveSubPath(item, subPath);
    }
    return parent?.resolve(path);
  }

  /// 针对字符串属性值解析其中内嵌的作用域插值变量
  dynamic resolveDynamic(dynamic val) {
    if (val is String) {
      if (!val.contains(r'$')) return val;
      return val.replaceAllMapped(DuiState._scopedVarPattern, (m) {
        final varName = m.group(1);
        if (varName != null) {
          final resolved = resolve(varName);
          return resolved?.toString() ?? '';
        }
        return '';
      });
    }
    return val;
  }

  static dynamic _resolveSubPath(dynamic target, String subPath) {
    if (target == null) return null;
    final segments = subPath.split('.');
    dynamic current = target;
    for (final seg in segments) {
      if (current == null) return null;
      if (current is Map) {
        current = current[seg];
      } else if (current is List) {
        final idx = int.tryParse(seg);
        if (idx != null && idx >= 0 && idx < current.length) {
          current = current[idx];
        } else {
          return null;
        }
      } else {
        return null;
      }
    }
    return current;
  }
}
