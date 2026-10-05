import 'package:lua_dardo/lua.dart';

/// `regex` — 强大的正则表达式处理 API。
///
/// 弥补 Lua 原生正则 pattern 语法的局限，支持标准 PCRE/ECMA 风格的正则匹配与替换。
class RegexApi {
  static void bind(LuaState ls) {
    ls.newTable();

    RegExp? parseRegex(LuaState ls, String pattern) {
      try {
        return RegExp(pattern);
      } catch (e) {
        ls.error2('非法正则表达式: $e');
        return null;
      }
    }

    // regex.test(pattern, text) -> bool
    ls.pushDartFunction((ls) {
      final pattern = ls.checkString(1) ?? '';
      final text = ls.checkString(2) ?? '';
      final re = parseRegex(ls, pattern);
      if (re == null) return 0;
      ls.pushBoolean(re.hasMatch(text));
      return 1;
    });
    ls.setField(-2, 'test');

    // regex.firstMatch(pattern, text) -> string | nil
    ls.pushDartFunction((ls) {
      final pattern = ls.checkString(1) ?? '';
      final text = ls.checkString(2) ?? '';
      final re = parseRegex(ls, pattern);
      if (re == null) return 0;
      final m = re.firstMatch(text);
      if (m != null && m.group(0) != null) {
        ls.pushString(m.group(0)!);
        return 1;
      }
      ls.pushNil();
      return 1;
    });
    ls.setField(-2, 'firstMatch');

    // regex.findAll(pattern, text) -> table (array of string)
    ls.pushDartFunction((ls) {
      final pattern = ls.checkString(1) ?? '';
      final text = ls.checkString(2) ?? '';
      final re = parseRegex(ls, pattern);
      if (re == null) return 0;
      final matches = re.allMatches(text);
      ls.newTable();
      int i = 1;
      for (final m in matches) {
        if (m.group(0) != null) {
          ls.pushInteger(i++);
          ls.pushString(m.group(0)!);
          ls.setTable(-3);
        }
      }
      return 1;
    });
    ls.setField(-2, 'findAll');

    // regex.replace(pattern, text, replacement) -> string
    ls.pushDartFunction((ls) {
      final pattern = ls.checkString(1) ?? '';
      final text = ls.checkString(2) ?? '';
      final replacement = ls.checkString(3) ?? '';
      final re = parseRegex(ls, pattern);
      if (re == null) return 0;
      final result = text.replaceFirst(re, replacement);
      ls.pushString(result);
      return 1;
    });
    ls.setField(-2, 'replace');

    // regex.replaceAll(pattern, text, replacement) -> string
    ls.pushDartFunction((ls) {
      final pattern = ls.checkString(1) ?? '';
      final text = ls.checkString(2) ?? '';
      final replacement = ls.checkString(3) ?? '';
      final re = parseRegex(ls, pattern);
      if (re == null) return 0;
      final result = text.replaceAll(re, replacement);
      ls.pushString(result);
      return 1;
    });
    ls.setField(-2, 'replaceAll');

    ls.setGlobal('regex');
  }
}
