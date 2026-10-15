/// 纯 Dart 轻量安全 XML 解析与序列化器
/// 杜绝 XXE 外部实体注入攻击，专注于轻量标记树解析与文档构造。
class XmlParser {
  /// 解析 XML 文本为节点树 Map:
  /// {
  ///   'tag': String,
  ///   'attrs': `Map<String, String>`,
  ///   'children': `List<Map>`,
  ///   'text': String?
  /// }
  static Map<String, dynamic>? parse(String xml) {
    var clean = xml.trim();
    // 移除 XML 声明 <?xml ... ?> 与注释 <!-- ... -->
    clean = clean.replaceAll(RegExp(r'<\?xml[\s\S]*?\?>'), '');
    clean = clean.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');
    // 彻底忽略 DOCTYPE 实体声明 (防御 XXE)
    clean = clean.replaceAll(
        RegExp(r'<!DOCTYPE[\s\S]*?>', caseSensitive: false), '');
    clean = clean.trim();
    if (clean.isEmpty) return null;

    final tokens = _tokenize(clean);
    int pos = 0;

    Map<String, dynamic>? parseElement() {
      if (pos >= tokens.length) return null;
      final startTok = tokens[pos++];
      if (!startTok.isStartTag) return null;

      final node = <String, dynamic>{
        'tag': startTok.name,
        'attrs': startTok.attrs,
        'children': <Map<String, dynamic>>[],
        'text': '',
      };

      if (startTok.isSelfClosing) {
        return node;
      }

      final textBuffer = StringBuffer();

      while (pos < tokens.length) {
        final tok = tokens[pos];
        if (tok.isText) {
          textBuffer.write(tok.text);
          pos++;
        } else if (tok.isStartTag) {
          final child = parseElement();
          if (child != null) {
            (node['children'] as List).add(child);
          }
        } else if (tok.isEndTag) {
          pos++;
          break;
        } else {
          pos++;
        }
      }

      final text = textBuffer.toString().trim();
      if (text.isNotEmpty) {
        node['text'] = _unescapeXml(text);
      }
      return node;
    }

    return parseElement();
  }

  static List<_XmlToken> _tokenize(String s) {
    final tokens = <_XmlToken>[];
    int i = 0;

    while (i < s.length) {
      if (s[i] == '<') {
        final closeIdx = s.indexOf('>', i);
        if (closeIdx == -1) break;
        final tagContent = s.substring(i + 1, closeIdx).trim();
        i = closeIdx + 1;

        if (tagContent.startsWith('/')) {
          tokens.add(_XmlToken.end(tagContent.substring(1).trim()));
        } else {
          bool selfClose = false;
          String body = tagContent;
          if (body.endsWith('/')) {
            selfClose = true;
            body = body.substring(0, body.length - 1).trim();
          }

          final spaceIdx = body.indexOf(RegExp(r'\s'));
          String tagName;
          Map<String, String> attrs = {};

          if (spaceIdx == -1) {
            tagName = body;
          } else {
            tagName = body.substring(0, spaceIdx);
            final attrStr = body.substring(spaceIdx + 1);
            attrs = _parseAttributes(attrStr);
          }

          tokens.add(_XmlToken.start(tagName, attrs, selfClose));
        }
      } else {
        final nextOpen = s.indexOf('<', i);
        final textPart =
            nextOpen == -1 ? s.substring(i) : s.substring(i, nextOpen);
        if (textPart.trim().isNotEmpty) {
          tokens.add(_XmlToken.text(textPart));
        }
        i = nextOpen == -1 ? s.length : nextOpen;
      }
    }

    return tokens;
  }

  static Map<String, String> _parseAttributes(String raw) {
    final attrs = <String, String>{};
    final regex = RegExp(r'([a-zA-Z0-9_\-:]+)\s*=\s*("([^"]*)"|' "'([^']*)')");
    for (final m in regex.allMatches(raw)) {
      final key = m.group(1)!;
      final val = m.group(3) ?? m.group(4) ?? '';
      attrs[key] = _unescapeXml(val);
    }
    return attrs;
  }

  static String _unescapeXml(String text) {
    return text
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&amp;', '&');
  }

  static String _escapeXml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  /// 序列化节点树为标准 XML 字符串
  static String stringify(Map<dynamic, dynamic> node, [int indent = 0]) {
    final sb = StringBuffer();
    final pad = '  ' * indent;

    final tag = node['tag']?.toString() ?? 'node';
    final rawAttrs = node['attrs'];
    final attrs = rawAttrs is Map ? rawAttrs : const {};

    final rawChildren = node['children'];
    final children = <Map<dynamic, dynamic>>[];
    if (rawChildren is List) {
      for (final c in rawChildren) {
        if (c is Map) children.add(c);
      }
    }
    final text = node['text']?.toString() ?? '';

    sb.write('$pad<$tag');
    attrs.forEach((k, v) {
      sb.write(' $k="${_escapeXml(v.toString())}"');
    });

    if (children.isEmpty && text.isEmpty) {
      sb.writeln(' />');
      return sb.toString();
    }

    sb.write('>');
    if (children.isEmpty) {
      sb.write(_escapeXml(text));
      sb.writeln('</$tag>');
    } else {
      sb.writeln();
      if (text.isNotEmpty) {
        sb.writeln('$pad  ${_escapeXml(text)}');
      }
      for (final child in children) {
        sb.write(stringify(child, indent + 1));
      }
      sb.writeln('$pad</$tag>');
    }

    return sb.toString();
  }
}

class _XmlToken {
  final bool isStartTag;
  final bool isEndTag;
  final bool isText;
  final bool isSelfClosing;
  final String name;
  final Map<String, String> attrs;
  final String text;

  _XmlToken.start(this.name, this.attrs, this.isSelfClosing)
      : isStartTag = true,
        isEndTag = false,
        isText = false,
        text = '';

  _XmlToken.end(this.name)
      : isStartTag = false,
        isEndTag = true,
        isText = false,
        isSelfClosing = false,
        attrs = const {},
        text = '';

  _XmlToken.text(this.text)
      : isStartTag = false,
        isEndTag = false,
        isText = true,
        isSelfClosing = false,
        name = '',
        attrs = const {};
}
