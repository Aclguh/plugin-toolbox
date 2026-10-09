import 'package:lua_dardo/lua.dart';

/// Dart 与 Lua 虚拟机之间数据类型双向编解码转换工具
class LuaValueCodec {
  /// 将 Dart 动态值压入 Lua 栈顶（递归转换 Map 与 List，拦截循环引用）
  static void push(LuaState ls, dynamic val, [Set<Object?>? visited]) {
    // 循环引用检测：自引用集合若不拦截将在递归压栈时栈溢出
    if (val is Map || val is List) {
      final seen = visited ??= <Object?>{};
      if (seen.contains(val)) {
        throw Exception('不支持将包含循环引用的集合转换为 Lua 值');
      }
      seen.add(val);
    }

    if (val == null) {
      ls.pushNil();
    } else if (val is bool) {
      ls.pushBoolean(val);
    } else if (val is int) {
      ls.pushInteger(val);
    } else if (val is double) {
      ls.pushNumber(val);
    } else if (val is String) {
      ls.pushString(val);
    } else if (val is Map) {
      ls.newTable();
      val.forEach((k, v) {
        ls.pushString(k.toString());
        push(ls, v, visited);
        ls.setTable(-3);
      });
    } else if (val is List) {
      ls.newTable();
      for (int i = 0; i < val.length; i++) {
        ls.pushInteger(i + 1);
        push(ls, val[i], visited);
        ls.setTable(-3);
      }
    } else {
      ls.pushString(val.toString());
    }

    visited?.remove(val);
  }

  /// 弹出 Lua 栈顶的值并转换为 Dart 原生类型（支持 Map, List 与基础标量）
  static dynamic pop(LuaState ls) {
    final type = ls.type(-1);
    dynamic result;
    switch (type) {
      case LuaType.luaNil:
        result = null;
        break;
      case LuaType.luaBoolean:
        result = ls.toBoolean(-1);
        break;
      case LuaType.luaNumber:
        result = ls.isInteger(-1) ? ls.toInteger(-1) : ls.toNumber(-1);
        break;
      case LuaType.luaString:
        result = ls.toStr(-1);
        break;
      case LuaType.luaTable:
        result = readTable(ls, -1);
        break;
      default:
        result = null;
    }
    ls.pop(1);
    return result;
  }

  static const int maxTableDepth = 64;

  /// 深度读取指定栈索引的 Lua 表结构并识别连续数组或字典（含循环引用与深度防护）
  static dynamic readTable(
    LuaState ls,
    int idx, [
    Set<Object?>? seenPointers,
    int depth = 0,
  ]) {
    if (depth > maxTableDepth) {
      return null;
    }
    final absIdx = idx < 0 ? ls.getTop() + idx + 1 : idx;
    final pointer = ls.toPointer(absIdx);
    final seen = seenPointers ?? <Object?>{};
    if (pointer != null && seen.contains(pointer)) {
      return null;
    }
    if (pointer != null) {
      seen.add(pointer);
    }

    final rawEntries = <dynamic, dynamic>{};
    ls.pushNil();
    while (ls.next(absIdx)) {
      final dynamic key = ls.isInteger(-2)
          ? ls.toInteger(-2)
          : (ls.toStr(-2) ?? ls.toInteger(-2).toString());
      final val = readCurrentValue(ls, seen, depth + 1);
      rawEntries[key] = val;
      ls.pop(1);
    }

    if (pointer != null) {
      seen.remove(pointer);
    }

    if (rawEntries.isEmpty) {
      return <String, dynamic>{};
    }

    // 检查是否为从 1 开始、连续到 N 的纯整数索引表（Lua 数组特征）
    bool isSequentialArray = true;
    for (int i = 1; i <= rawEntries.length; i++) {
      if (!rawEntries.containsKey(i)) {
        isSequentialArray = false;
        break;
      }
    }

    if (isSequentialArray) {
      final list = List<dynamic>.filled(rawEntries.length, null, growable: true);
      for (int i = 1; i <= rawEntries.length; i++) {
        list[i - 1] = rawEntries[i];
      }
      return list;
    }

    // 否则作为 Map<String, dynamic> 返回
    final map = <String, dynamic>{};
    for (final entry in rawEntries.entries) {
      map[entry.key.toString()] = entry.value;
    }
    return map;
  }

  /// 读取当前栈顶的值但不弹出
  static dynamic readCurrentValue(
    LuaState ls, [
    Set<Object?>? seenPointers,
    int depth = 0,
  ]) {
    final type = ls.type(-1);
    switch (type) {
      case LuaType.luaNil:
        return null;
      case LuaType.luaBoolean:
        return ls.toBoolean(-1);
      case LuaType.luaNumber:
        return ls.isInteger(-1) ? ls.toInteger(-1) : ls.toNumber(-1);
      case LuaType.luaString:
        return ls.toStr(-1);
      case LuaType.luaTable:
        return readTable(ls, -1, seenPointers, depth);
      default:
        return null;
    }
  }
}
