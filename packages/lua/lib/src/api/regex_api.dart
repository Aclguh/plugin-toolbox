import 'package:lua_dardo/lua.dart';

/// `regex` — 强大的正则表达式处理 API。
///
/// 弥补 Lua 原生正则 pattern 语法的局限，支持标准 PCRE/ECMA 风格的正则匹配与替换。
///
/// Dart RegExp 为回溯型引擎，插件传入的恶意模式（如 `(a+)+$`）可触发灾难性
/// 回溯冻结宿主主线程（ReDoS）。由于 Dart 正则无超时机制且正则匹配必须在
/// Lua 同步栈内返回结果（无法异步化），此处采用务实的静态防御：
/// 限制模式长度、拦截嵌套量词特征模式、限制输入文本长度。
class RegexApi {
  /// 模式串长度上限：正常业务正则极少超过百字符，超长模式多为攻击性构造
  static const int maxPatternLength = 256;

  /// 输入文本长度上限（1MB）：放大回溯耗时的长输入一律拒绝
  static const int maxTextLength = 1024 * 1024;

  /// 灾难性回溯的典型特征：组内已含量词、组外再叠加量词（如 `(a+)+`、`(\d*)*`）。
  /// 合法业务正则几乎不写嵌套量词，拦截成本低、误伤面小。
  static final RegExp _nestedQuantifier =
      RegExp(r'\((?:[^()\\]|\\[\s\S])*[+*](?:[^()\\]|\\[\s\S])*\)\s*[+*?{]');

  static void bind(LuaState ls) {
    ls.newTable();

    RegExp? parseRegex(LuaState ls, String pattern) {
      if (pattern.length > maxPatternLength) {
        ls.error2('正则模式超长: 超过 $maxPatternLength 字符上限');
        return null;
      }
      if (_nestedQuantifier.hasMatch(pattern)) {
        ls.error2('正则模式被拒绝: 嵌套量词可能引发灾难性回溯 (ReDoS)');
        return null;
      }
      try {
        return RegExp(pattern);
      } catch (e) {
        ls.error2('非法正则表达式: $e');
        return null;
      }
    }

    bool checkText(LuaState ls, String text) {
      if (text.length > maxTextLength) {
        ls.error2('输入文本超长: 超过 ${maxTextLength ~/ (1024 * 1024)}MB 正则处理上限');
        return false;
      }
      return true;
    }

    // regex.test(pattern, text) -> bool
    ls.pushDartFunction((ls) {
      final pattern = ls.checkString(1) ?? '';
      final text = ls.checkString(2) ?? '';
      if (!checkText(ls, text)) return 0;
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
      if (!checkText(ls, text)) return 0;
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
      if (!checkText(ls, text)) return 0;
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
      if (!checkText(ls, text)) return 0;
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
      if (!checkText(ls, text)) return 0;
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
