import 'package:lua_dardo/lua.dart';

/// `document` — 文档解析与格式转换 API。
///
/// 提供 CSV 与 Markdown 格式的纯文本解析与序列化支持。
class DocumentApi {
  static void bind(LuaState ls) {
    ls.newTable();

    // document.csvParse(content) -> table (array of rows)
    ls.pushDartFunction((ls) {
      final content = ls.checkString(1) ?? '';
      final rows = parseCsv(content);

      ls.newTable();
      for (int r = 0; r < rows.length; r++) {
        ls.pushInteger(r + 1);
        ls.newTable();
        final row = rows[r];
        for (int c = 0; c < row.length; c++) {
          ls.pushInteger(c + 1);
          ls.pushString(row[c]);
          ls.setTable(-3);
        }
        ls.setTable(-3);
      }
      return 1;
    });
    ls.setField(-2, 'csvParse');

    // document.csvStringify(table) -> string
    ls.pushDartFunction((ls) {
      if (ls.type(1) != LuaType.luaTable) {
        ls.error2('参数必须为表结构 (二维数组)');
        return 0;
      }

      final rows = <List<String>>[];
      final rowCount = ls.rawLen(1);
      for (int r = 1; r <= rowCount; r++) {
        ls.pushInteger(r);
        ls.getTable(1);
        if (ls.type(-1) == LuaType.luaTable) {
          final colCount = ls.rawLen(-1);
          final row = <String>[];
          for (int c = 1; c <= colCount; c++) {
            ls.pushInteger(c);
            ls.getTable(-2);
            row.add(ls.toStr(-1) ?? '');
            ls.pop(1);
          }
          rows.add(row);
        }
        ls.pop(1);
      }

      final csvStr = stringifyCsv(rows);
      ls.pushString(csvStr);
      return 1;
    });
    ls.setField(-2, 'csvStringify');

    // document.markdownToHtml(markdown) -> string
    ls.pushDartFunction((ls) {
      final md = ls.checkString(1) ?? '';
      final html = markdownToHtml(md);
      ls.pushString(html);
      return 1;
    });
    ls.setField(-2, 'markdownToHtml');

    ls.setGlobal('document');
  }

  /// 标准 CSV 解析算法，支持引号字段与转义
  static List<List<String>> parseCsv(String input) {
    final rows = <List<String>>[];
    final currentRow = <String>[];
    final currentField = StringBuffer();
    bool inQuotes = false;
    int i = 0;

    while (i < input.length) {
      final char = input[i];

      if (inQuotes) {
        if (char == '"') {
          if (i + 1 < input.length && input[i + 1] == '"') {
            currentField.write('"');
            i += 2;
            continue;
          } else {
            inQuotes = false;
          }
        } else {
          currentField.write(char);
        }
      } else {
        if (char == '"') {
          inQuotes = true;
        } else if (char == ',') {
          currentRow.add(currentField.toString());
          currentField.clear();
        } else if (char == '\r') {
          if (i + 1 < input.length && input[i + 1] == '\n') {
            i++;
          }
          currentRow.add(currentField.toString());
          currentField.clear();
          rows.add(List.from(currentRow));
          currentRow.clear();
        } else if (char == '\n') {
          currentRow.add(currentField.toString());
          currentField.clear();
          rows.add(List.from(currentRow));
          currentRow.clear();
        } else {
          currentField.write(char);
        }
      }
      i++;
    }

    if (currentField.isNotEmpty || currentRow.isNotEmpty) {
      currentRow.add(currentField.toString());
      rows.add(currentRow);
    }

    return rows;
  }

  /// 标准 CSV 序列化
  static String stringifyCsv(List<List<String>> rows) {
    final sb = StringBuffer();
    for (int r = 0; r < rows.length; r++) {
      final row = rows[r];
      for (int c = 0; c < row.length; c++) {
        final val = row[c];
        if (val.contains(',') || val.contains('"') || val.contains('\n') || val.contains('\r')) {
          sb.write('"');
          sb.write(val.replaceAll('"', '""'));
          sb.write('"');
        } else {
          sb.write(val);
        }
        if (c < row.length - 1) sb.write(',');
      }
      if (r < rows.length - 1) sb.write('\r\n');
    }
    return sb.toString();
  }

  /// 轻量 Markdown 转 HTML 实现
  static String markdownToHtml(String md) {
    final lines = md.split(RegExp(r'\r?\n'));
    final sb = StringBuffer();
    bool inCodeBlock = false;
    bool inList = false;

    for (final line in lines) {
      final trimmed = line.trim();

      // 代码块检测
      if (trimmed.startsWith('```')) {
        if (inCodeBlock) {
          sb.writeln('</code></pre>');
          inCodeBlock = false;
        } else {
          if (inList) {
            sb.writeln('</ul>');
            inList = false;
          }
          final lang = trimmed.substring(3).trim();
          sb.write('<pre><code${lang.isNotEmpty ? ' class="language-$lang"' : ''}>');
          inCodeBlock = true;
        }
        continue;
      }

      if (inCodeBlock) {
        sb.writeln(_escapeHtml(line));
        continue;
      }

      // 列表处理
      if (trimmed.startsWith('- ') || trimmed.startsWith('* ')) {
        if (!inList) {
          sb.writeln('<ul>');
          inList = true;
        }
        final itemContent = _parseInline(trimmed.substring(2));
        sb.writeln('  <li>$itemContent</li>');
        continue;
      } else if (inList) {
        sb.writeln('</ul>');
        inList = false;
      }

      // 空行
      if (trimmed.isEmpty) {
        continue;
      }

      // 标题
      if (trimmed.startsWith('#')) {
        int level = 0;
        while (level < trimmed.length && trimmed[level] == '#') {
          level++;
        }
        if (level >= 1 && level <= 6 && trimmed.length > level && trimmed[level] == ' ') {
          final content = _parseInline(trimmed.substring(level + 1));
          sb.writeln('<h$level>$content</h$level>');
          continue;
        }
      }

      // 引用
      if (trimmed.startsWith('> ')) {
        final content = _parseInline(trimmed.substring(2));
        sb.writeln('<blockquote>$content</blockquote>');
        continue;
      }

      // 水平分割线
      if (trimmed == '---' || trimmed == '***' || trimmed == '___') {
        sb.writeln('<hr />');
        continue;
      }

      // 普通段落
      sb.writeln('<p>${_parseInline(line)}</p>');
    }

    if (inCodeBlock) sb.writeln('</code></pre>');
    if (inList) sb.writeln('</ul>');

    return sb.toString().trim();
  }

  static String _parseInline(String text) {
    String res = _escapeHtml(text);
    // 行内代码 `code`
    res = res.replaceAllMapped(RegExp(r'`([^`]+)`'), (m) => '<code>${m[1]}</code>');
    // 加粗 **bold**
    res = res.replaceAllMapped(RegExp(r'\*\*([^*]+)\*\*'), (m) => '<strong>${m[1]}</strong>');
    // 斜体 *italic*
    res = res.replaceAllMapped(RegExp(r'\*([^*]+)\*'), (m) => '<em>${m[1]}</em>');
    // 删除线 ~~del~~
    res = res.replaceAllMapped(RegExp(r'~~([^~]+)~~'), (m) => '<del>${m[1]}</del>');
    // 链接 [text](url)
    res = res.replaceAllMapped(RegExp(r'\[([^\]]+)\]\(([^)]+)\)'), (m) => '<a href="${m[2]}">${m[1]}</a>');
    return res;
  }

  static String _escapeHtml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;');
  }
}
