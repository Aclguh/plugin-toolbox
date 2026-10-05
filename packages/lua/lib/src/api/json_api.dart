import 'dart:convert';
import 'package:lua_dardo/lua.dart';

/// JSON 编解码绑定（同步纯函数，无权限门槛）。
///
/// `json.encode(value)` 将 Lua 值序列化为 JSON 字符串：连续 1..N 整数索引的表
/// 序列化为数组，其余表序列化为对象（非字符串/数字键跳过）；函数/userdata
/// 等不可序列化类型与循环引用、超深嵌套一律抛 Lua 错误，由脚本侧 pcall 兜底。
/// `json.decode(text)` 将 JSON 文本解析为 Lua 值：数组为 1 起始表、对象为
/// 字符串键表；null 依 Lua 表语义映射为「键缺失」（向表赋 nil 即删除键），
/// 顶层 null 为 nil；非法文本抛 Lua 错误。
///
/// 嵌套深度上限双向生效：encode 侧防 Lua 侧自引用深表；decode 侧先做文本
/// 括号深度预检，防止恶意深嵌套输入在 Dart jsonDecode 递归解析时击穿调用栈
/// （该解析发生在宿主侧，指令数预算无法覆盖）。
class JsonApi {
  /// Lua/Dart 双向递归转换的最大嵌套层级
  static const int maxDepth = 64;

  static void bind(LuaState ls) {
    ls.newTable();

    ls.pushDartFunction((ls) {
      if (ls.getTop() < 1) {
        ls.error2('json.encode 缺少参数: 需要一个可序列化值');
        return 0;
      }
      final seen = <Object?>{};
      final dart = _readValue(ls, 1, seen, 0);
      final String encoded;
      try {
        encoded = jsonEncode(dart);
      } on JsonUnsupportedObjectError catch (e) {
        ls.error2('JSON 序列化失败: 无法序列化 ${e.unsupportedObject}');
        return 0;
      }
      ls.pushString(encoded);
      return 1;
    });
    ls.setField(-2, 'encode');

    ls.pushDartFunction((ls) {
      final text = ls.checkString(1) ?? '';
      final depth = _textBracketDepth(text);
      if (depth > maxDepth) {
        ls.error2('JSON 解析失败: 嵌套层级超过 $maxDepth');
        return 0;
      }
      final Object? decoded;
      try {
        decoded = jsonDecode(text);
      } on FormatException catch (e) {
        ls.error2('JSON 解析失败: ${e.message}');
        return 0;
      }
      _pushValue(ls, decoded, 0);
      return 1;
    });
    ls.setField(-2, 'decode');

    ls.setGlobal('json');
  }

  /// Lua 栈上 [idx] 处的值转为 Dart 可 JSON 序列化结构（不弹出栈）
  static dynamic _readValue(LuaState ls, int idx, Set<Object?> seen, int depth) {
    if (depth > maxDepth) {
      ls.error2('JSON 序列化失败: 嵌套层级超过 $maxDepth');
    }
    switch (ls.type(idx)) {
      case LuaType.luaNil:
        return null;
      case LuaType.luaBoolean:
        return ls.toBoolean(idx);
      case LuaType.luaNumber:
        return ls.isInteger(idx) ? ls.toInteger(idx) : ls.toNumber(idx);
      case LuaType.luaString:
        return ls.toStr(idx);
      case LuaType.luaTable:
        return _readTable(ls, idx, seen, depth);
      default:
        ls.error2('JSON 序列化失败: 不支持的类型 ${ls.typeName2(idx)}');
        return null;
    }
  }

  static dynamic _readTable(LuaState ls, int idx, Set<Object?> seen, int depth) {
    // 绝对索引在 pushNil/递归期间保持稳定, next 迭代器状态挂在该表的栈槽上
    final absIdx = idx < 0 ? ls.getTop() + idx + 1 : idx;
    final identity = ls.toPointer(absIdx);
    if (seen.contains(identity)) {
      ls.error2('JSON 序列化失败: 表存在循环引用');
    }
    seen.add(identity);
    final entries = <dynamic, dynamic>{};
    ls.pushNil();
    while (ls.next(absIdx)) {
      final keyType = ls.type(-2);
      dynamic key;
      if (keyType == LuaType.luaString) {
        key = ls.toStr(-2);
      } else if (keyType == LuaType.luaNumber) {
        key = ls.isInteger(-2) ? ls.toInteger(-2) : ls.toNumber(-2);
      } else {
        // 函数/表等键无法映射进 JSON, 跳过而非整体失败
        ls.pop(1);
        continue;
      }
      entries[key] = _readValue(ls, -1, seen, depth + 1);
      ls.pop(1);
    }
    seen.remove(identity);

    if (entries.isEmpty) {
      return <String, dynamic>{};
    }

    // 与 LuaEngine._readTable 同判据: 1..N 连续整数键视为数组
    var isSequentialArray = true;
    for (var i = 1; i <= entries.length; i++) {
      if (!entries.containsKey(i)) {
        isSequentialArray = false;
        break;
      }
    }
    if (isSequentialArray) {
      return [for (var i = 1; i <= entries.length; i++) entries[i]];
    }
    return {for (final e in entries.entries) e.key.toString(): e.value};
  }

  /// Dart 结构压入 Lua 栈（表转为 1 起始数组表或字符串键表）
  static void _pushValue(LuaState ls, Object? val, int depth) {
    if (depth > maxDepth) {
      ls.error2('JSON 解析失败: 嵌套层级超过 $maxDepth');
    }
    if (val == null) {
      ls.pushNil();
    } else if (val is bool) {
      ls.pushBoolean(val);
    } else if (val is int) {
      ls.pushInteger(val);
    } else if (val is num) {
      ls.pushNumber(val.toDouble());
    } else if (val is String) {
      ls.pushString(val);
    } else if (val is List) {
      ls.newTable();
      for (var i = 0; i < val.length; i++) {
        ls.pushInteger(i + 1);
        _pushValue(ls, val[i], depth + 1);
        ls.setTable(-3);
      }
    } else if (val is Map) {
      ls.newTable();
      val.forEach((k, v) {
        ls.pushString(k.toString());
        _pushValue(ls, v, depth + 1);
        ls.setTable(-3);
      });
    } else {
      ls.pushString(val.toString());
    }
  }

  /// 统计文本中不在字符串字面量内的 {}[] 最大嵌套深度
  static int _textBracketDepth(String text) {
    var depth = 0, maxDepthSeen = 0;
    var inString = false, escaped = false;
    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (ch == r'\') {
          escaped = true;
        } else if (ch == '"') {
          inString = false;
        }
        continue;
      }
      if (ch == '"') {
        inString = true;
      } else if (ch == '{' || ch == '[') {
        depth++;
        if (depth > maxDepthSeen) maxDepthSeen = depth;
      } else if (ch == '}' || ch == ']') {
        depth--;
        if (depth < 0) depth = 0;
      }
    }
    return maxDepthSeen;
  }
}
