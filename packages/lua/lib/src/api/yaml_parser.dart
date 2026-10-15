/// 纯 Dart 轻量安全 YAML 解析与序列化器
/// 专注于配置数据与工具箱轻量数据交换，支持标准缩进、键值对映射、列表序列、基础数据类型。
class YamlParser {
  /// 解析 YAML 文本为 Dart 对象 (Map, List, 或基本类型)
  static dynamic parse(String input) {
    final lines = input.split(RegExp(r'\r?\n'));
    final cleanLines = <_YamlLine>[];

    for (int i = 0; i < lines.length; i++) {
      final raw = lines[i];
      // 忽略纯空白行
      if (raw.trim().isEmpty) continue;
      // 提取缩进与内容
      int indent = 0;
      while (indent < raw.length && raw[indent] == ' ') {
        indent++;
      }
      final content = raw.substring(indent);
      // 忽略纯注释行
      if (content.startsWith('#')) continue;
      // 去除行末尾注释 (若不在引号内)
      final stripped = _stripComment(content);
      if (stripped.trim().isEmpty) continue;

      cleanLines.add(_YamlLine(indent: indent, text: stripped.trimRight()));
    }

    if (cleanLines.isEmpty) return null;

    final index = _IntRef(0);
    return _parseNode(cleanLines, index, -1);
  }

  static String _stripComment(String line) {
    bool inQuote = false;
    String quoteChar = '';
    for (int i = 0; i < line.length; i++) {
      final c = line[i];
      if ((c == '"' || c == "'") && (i == 0 || line[i - 1] != '\\')) {
        if (!inQuote) {
          inQuote = true;
          quoteChar = c;
        } else if (c == quoteChar) {
          inQuote = false;
        }
      } else if (c == '#' && !inQuote) {
        return line.substring(0, i);
      }
    }
    return line;
  }

  static dynamic _parseNode(
      List<_YamlLine> lines, _IntRef index, int parentIndent) {
    if (index.value >= lines.length) return null;

    final firstLine = lines[index.value];
    if (firstLine.text.startsWith('- ') || firstLine.text == '-') {
      // 列表节点
      final list = <dynamic>[];
      final currentIndent = firstLine.indent;

      while (index.value < lines.length) {
        final line = lines[index.value];
        if (line.indent < currentIndent) break;
        if (line.indent == currentIndent &&
            (line.text.startsWith('- ') || line.text == '-')) {
          index.value++;
          final itemStr =
              line.text.startsWith('- ') ? line.text.substring(2).trim() : '';
          if (itemStr.isEmpty) {
            // 子对象
            if (index.value < lines.length &&
                lines[index.value].indent > currentIndent) {
              list.add(_parseNode(lines, index, currentIndent));
            } else {
              list.add(null);
            }
          } else if (itemStr.contains(': ') || itemStr.endsWith(':')) {
            // 嵌套 map: - key: val
            final colon = itemStr.indexOf(':');
            final k = itemStr.substring(0, colon).trim();
            final vStr = itemStr.substring(colon + 1).trim();
            final subMap = <String, dynamic>{};
            if (vStr.isNotEmpty) {
              subMap[k] = _parseScalar(vStr);
            } else if (index.value < lines.length &&
                lines[index.value].indent > currentIndent) {
              subMap[k] = _parseNode(lines, index, currentIndent);
            } else {
              subMap[k] = null;
            }
            // 后续同级 Map 行
            while (index.value < lines.length &&
                lines[index.value].indent > currentIndent) {
              final subLine = lines[index.value];
              if (subLine.text.contains(':')) {
                index.value++;
                final c = subLine.text.indexOf(':');
                final subK = subLine.text.substring(0, c).trim();
                final subV = subLine.text.substring(c + 1).trim();
                if (subV.isNotEmpty) {
                  subMap[subK] = _parseScalar(subV);
                } else if (index.value < lines.length &&
                    lines[index.value].indent > subLine.indent) {
                  subMap[subK] = _parseNode(lines, index, subLine.indent);
                } else {
                  subMap[subK] = null;
                }
              } else {
                break;
              }
            }
            list.add(subMap);
          } else {
            list.add(_parseScalar(itemStr));
          }
        } else {
          break;
        }
      }
      return list;
    } else if (firstLine.text.contains(':')) {
      // 字典节点
      final map = <String, dynamic>{};
      final currentIndent = firstLine.indent;

      while (index.value < lines.length) {
        final line = lines[index.value];
        if (line.indent < currentIndent) break;
        if (line.indent == currentIndent && line.text.contains(':')) {
          index.value++;
          final colonIdx = line.text.indexOf(':');
          final key = line.text.substring(0, colonIdx).trim();
          final valStr = line.text.substring(colonIdx + 1).trim();

          if (valStr.isNotEmpty) {
            map[key] = _parseScalar(valStr);
          } else {
            if (index.value < lines.length &&
                lines[index.value].indent > currentIndent) {
              map[key] = _parseNode(lines, index, currentIndent);
            } else {
              map[key] = null;
            }
          }
        } else {
          break;
        }
      }
      return map;
    } else {
      // 单一标量
      index.value++;
      return _parseScalar(firstLine.text);
    }
  }

  static dynamic _parseScalar(String raw) {
    final str = raw.trim();
    if (str.isEmpty || str == '~' || str == 'null') return null;
    if (str == 'true' || str == 'True') return true;
    if (str == 'false' || str == 'False') return false;

    // 引号字符串
    if ((str.startsWith('"') && str.endsWith('"')) ||
        (str.startsWith("'") && str.endsWith("'"))) {
      if (str.length >= 2) {
        return str.substring(1, str.length - 1);
      }
    }

    // 整数与浮点数
    final intVal = int.tryParse(str);
    if (intVal != null) return intVal;
    final doubleVal = double.tryParse(str);
    if (doubleVal != null) return doubleVal;

    return str;
  }

  /// 序列化 Dart 对象为 YAML 文本
  static String stringify(dynamic object, [int indent = 0]) {
    final sb = StringBuffer();
    final pad = ' ' * indent;

    if (object is Map) {
      object.forEach((key, value) {
        if (value is Map) {
          sb.writeln('$pad$key:');
          sb.write(stringify(value, indent + 2));
        } else if (value is List) {
          sb.writeln('$pad$key:');
          sb.write(stringify(value, indent + 2));
        } else {
          sb.writeln('$pad$key: ${_formatScalar(value)}');
        }
      });
    } else if (object is List) {
      for (final item in object) {
        if (item is Map) {
          sb.writeln('$pad-');
          sb.write(stringify(item, indent + 2));
        } else if (item is List) {
          sb.writeln('$pad-');
          sb.write(stringify(item, indent + 2));
        } else {
          sb.writeln('$pad- ${_formatScalar(item)}');
        }
      }
    } else {
      sb.writeln('$pad${_formatScalar(object)}');
    }

    return sb.toString();
  }

  static String _formatScalar(dynamic value) {
    if (value == null) return 'null';
    if (value is bool) return value ? 'true' : 'false';
    if (value is num) return value.toString();
    final str = value.toString();
    if (str.contains('\n') ||
        str.contains(':') ||
        str.contains('#') ||
        str.startsWith('-')) {
      return '"${str.replaceAll('"', r'\"')}"';
    }
    return str;
  }
}

class _YamlLine {
  final int indent;
  final String text;
  const _YamlLine({required this.indent, required this.text});
}

class _IntRef {
  int value;
  _IntRef(this.value);
}
