/// 预编译的 DUI 条件表达式抽象语法树 (AST)
abstract class DuiParsedExpression {
  bool evaluate(Map<String, dynamic> stateValues);
}

class _ConstExpr implements DuiParsedExpression {
  final bool value;
  const _ConstExpr(this.value);
  @override
  bool evaluate(Map<String, dynamic> stateValues) => value;
}

class _OrExpr implements DuiParsedExpression {
  final List<DuiParsedExpression> children;
  _OrExpr(this.children);
  @override
  bool evaluate(Map<String, dynamic> stateValues) {
    for (final child in children) {
      if (child.evaluate(stateValues)) return true;
    }
    return false;
  }
}

class _AndExpr implements DuiParsedExpression {
  final List<DuiParsedExpression> children;
  _AndExpr(this.children);
  @override
  bool evaluate(Map<String, dynamic> stateValues) {
    for (final child in children) {
      if (!child.evaluate(stateValues)) return false;
    }
    return true;
  }
}

class _NotExpr implements DuiParsedExpression {
  final DuiParsedExpression inner;
  _NotExpr(this.inner);
  @override
  bool evaluate(Map<String, dynamic> stateValues) =>
      !inner.evaluate(stateValues);
}

class _ComparisonExpr implements DuiParsedExpression {
  final _DuiOperand left;
  final _DuiOperand right;
  final String op;
  _ComparisonExpr(this.left, this.right, this.op);
  @override
  bool evaluate(Map<String, dynamic> stateValues) {
    final l = left.resolve(stateValues);
    final r = right.resolve(stateValues);
    return DuiExpressionEvaluator._compare(l, r, op);
  }
}

class _TruthyExpr implements DuiParsedExpression {
  final _DuiOperand operand;
  _TruthyExpr(this.operand);
  @override
  bool evaluate(Map<String, dynamic> stateValues) {
    return DuiExpressionEvaluator._isTruthy(operand.resolve(stateValues));
  }
}

abstract class _DuiOperand {
  dynamic resolve(Map<String, dynamic> values);
}

class _LiteralOperand implements _DuiOperand {
  final dynamic value;
  const _LiteralOperand(this.value);
  @override
  dynamic resolve(Map<String, dynamic> values) => value;
}

class _StateVarOperand implements _DuiOperand {
  final String path;
  final bool isDirect;
  _StateVarOperand(this.path) : isDirect = !path.contains('.');
  @override
  dynamic resolve(Map<String, dynamic> values) {
    if (isDirect) {
      if (values.containsKey(path)) return values[path];
      return path;
    }
    final res = DuiExpressionEvaluator._resolvePath(path, values);
    return res ?? path;
  }
}

/// 轻量条件表达式解析与计算器，支持 AST 预编译、LRU 缓存、数值比较、逻辑复合与类型推导
class DuiExpressionEvaluator {
  static final Map<String, DuiParsedExpression> _astCache = {};
  static const int _maxAstCacheSize = 512;

  /// 将原始表达式字符串预编译为高效的 AST 语法树（带静态缓存）
  static DuiParsedExpression compile(String rawExpr) {
    var expr = rawExpr.trim();
    if (expr.isEmpty || expr == 'true') return const _ConstExpr(true);
    if (expr == 'false') return const _ConstExpr(false);

    if (expr.startsWith('{{') && expr.endsWith('}}')) {
      expr = expr.substring(2, expr.length - 2).trim();
    }
    if (expr.isEmpty) return const _ConstExpr(true);

    final cached = _astCache[expr];
    if (cached != null) return cached;

    if (_astCache.length >= _maxAstCacheSize) {
      _astCache.clear();
    }

    try {
      final parsed = _parseOr(expr);
      _astCache[expr] = parsed;
      return parsed;
    } catch (_) {
      return const _ConstExpr(true);
    }
  }

  /// 快速求值接口（直接命中 AST 缓存进行高效计算）
  static bool evaluate(String rawExpr, Map<String, dynamic> stateValues) {
    return compile(rawExpr).evaluate(stateValues);
  }

  static DuiParsedExpression _parseOr(String expr) {
    final parts = _splitTopLevel(expr, '||');
    if (parts.length > 1) {
      return _OrExpr(parts.map(_parseAnd).toList());
    }
    return _parseAnd(expr);
  }

  static DuiParsedExpression _parseAnd(String expr) {
    final parts = _splitTopLevel(expr, '&&');
    if (parts.length > 1) {
      return _AndExpr(parts.map(_parseComparison).toList());
    }
    return _parseComparison(expr);
  }

  static DuiParsedExpression _parseComparison(String rawExpr) {
    final expr = rawExpr.trim();
    if (expr.isEmpty) return const _ConstExpr(true);

    if (expr.startsWith('!') && !expr.startsWith('!=')) {
      final inner = expr.substring(1).trim();
      return _NotExpr(_parseComparison(inner));
    }

    const ops = ['==', '!=', '>=', '<=', '>', '<'];
    for (final op in ops) {
      final idx = _indexOfOp(expr, op);
      if (idx != -1) {
        final leftStr = expr.substring(0, idx).trim();
        final rightStr = expr.substring(idx + op.length).trim();
        final leftOp = _parseOperand(leftStr);
        final rightOp = _parseOperand(rightStr);
        return _ComparisonExpr(leftOp, rightOp, op);
      }
    }

    final operand = _parseOperand(expr);
    return _TruthyExpr(operand);
  }

  static _DuiOperand _parseOperand(String raw) {
    var s = raw.trim();
    if (s.startsWith('{{') && s.endsWith('}}')) {
      s = s.substring(2, s.length - 2).trim();
    }
    if (s.isEmpty) return const _LiteralOperand(null);

    // 字符串字面量: '...' 或 "..."
    if ((s.startsWith("'") && s.endsWith("'") && s.length >= 2) ||
        (s.startsWith('"') && s.endsWith('"') && s.length >= 2)) {
      return _LiteralOperand(s.substring(1, s.length - 1));
    }

    // 布尔与空
    if (s == 'true') return const _LiteralOperand(true);
    if (s == 'false') return const _LiteralOperand(false);
    if (s == 'null') return const _LiteralOperand(null);

    // 数字
    final numVal = num.tryParse(s);
    if (numVal != null) return _LiteralOperand(numVal);

    // 状态变量引用: state.key 或 key
    if (s.startsWith('state.')) {
      final key = s.substring(6).trim();
      return _StateVarOperand(key);
    }
    return _StateVarOperand(s);
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
