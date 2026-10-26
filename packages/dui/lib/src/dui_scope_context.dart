/// 列表项等子树局部作用域环境，封装 $item 与 $index，支持嵌套继承与深度点号解析
class DuiScopeContext {
  static final RegExp _scopedVarPattern =
      RegExp(r'\{\{\s*(\$(?:index|item(?:\.[a-zA-Z0-9_]+)*))\s*\}\}');

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
      return val.replaceAllMapped(_scopedVarPattern, (m) {
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
