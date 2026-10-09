import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'dui_utils.dart';

/// 声明式 DUI HTML/富文本组件。
///
/// 纯 Dart 轻量标签解析，无需 WebView 或沉重外部库。
/// 支持常见标签：`<b>`, `<i>`, `<u>`, `<s>`, `<code>`, `<a href="...">`,
/// `<color value="...">`, `<h1>`-`<h6>`, `<p>`, `<br>`, `<li>` 等。
class DuiHtml extends StatefulWidget {
  final String html;
  final TextStyle? baseStyle;
  final bool selectable;
  final void Function(String url)? onLinkTap;

  const DuiHtml({
    super.key,
    required this.html,
    this.baseStyle,
    this.selectable = true,
    this.onLinkTap,
  });

  @override
  State<DuiHtml> createState() => _DuiHtmlState();
}

class _DuiHtmlState extends State<DuiHtml> {
  final List<TapGestureRecognizer> _recognizers = [];

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();

    final theme = Theme.of(context);
    final defaultStyle = widget.baseStyle ??
        theme.textTheme.bodyMedium ??
        const TextStyle(fontSize: 14.0);

    final span = _HtmlParser(
      theme: theme,
      baseStyle: defaultStyle,
      onLinkTap: widget.onLinkTap,
      recognizers: _recognizers,
    ).parse(widget.html);

    if (widget.selectable) {
      return SelectableText.rich(span);
    }
    return Text.rich(span);
  }
}

class _HtmlTag {
  final String name;
  final Map<String, String> attributes;
  final bool isClosing;
  final bool isSelfClosing;

  _HtmlTag({
    required this.name,
    required this.attributes,
    required this.isClosing,
    required this.isSelfClosing,
  });
}

class _HtmlParser {
  final ThemeData theme;
  final TextStyle baseStyle;
  final void Function(String url)? onLinkTap;
  final List<TapGestureRecognizer>? recognizers;

  _HtmlParser({
    required this.theme,
    required this.baseStyle,
    this.onLinkTap,
    this.recognizers,
  });

  TextSpan parse(String rawHtml) {
    if (rawHtml.isEmpty) {
      return TextSpan(text: '', style: baseStyle);
    }

    final spans = <InlineSpan>[];
    final tagRegex = RegExp(r'<(/?[a-zA-Z0-9]+)([^>]*)>');
    int currentIndex = 0;

    final activeStyles = <TextStyle>[baseStyle];
    final activeHrefs = <String?>[null];

    for (final match in tagRegex.allMatches(rawHtml)) {
      if (match.start > currentIndex) {
        final text = _decodeEntities(rawHtml.substring(currentIndex, match.start));
        if (text.isNotEmpty) {
          spans.add(_buildSpan(
            text,
            _combineStyles(activeStyles),
            activeHrefs.last,
          ));
        }
      }

      final rawTagName = match.group(1) ?? '';
      final rawAttrs = match.group(2) ?? '';
      final tag = _parseTag(rawTagName, rawAttrs);

      if (tag.isSelfClosing || tag.name == 'br') {
        spans.add(const TextSpan(text: '\n'));
      } else if (tag.isClosing) {
        if (tag.name == 'p' || tag.name.startsWith('h')) {
          spans.add(const TextSpan(text: '\n\n'));
        } else if (tag.name == 'li') {
          spans.add(const TextSpan(text: '\n'));
        }

        if (activeStyles.length > 1) {
          activeStyles.removeLast();
        }
        if (activeHrefs.length > 1) {
          activeHrefs.removeLast();
        }
      } else {
        // 开标签
        final currentTopStyle = activeStyles.last;
        TextStyle newStyle = currentTopStyle;
        String? newHref = activeHrefs.last;

        switch (tag.name) {
          case 'b':
          case 'strong':
            newStyle = currentTopStyle.copyWith(fontWeight: FontWeight.bold);
            break;
          case 'i':
          case 'em':
            newStyle = currentTopStyle.copyWith(fontStyle: FontStyle.italic);
            break;
          case 'u':
            newStyle = currentTopStyle.copyWith(decoration: TextDecoration.underline);
            break;
          case 's':
          case 'del':
          case 'strike':
            newStyle = currentTopStyle.copyWith(decoration: TextDecoration.lineThrough);
            break;
          case 'code':
            newStyle = currentTopStyle.copyWith(
              fontFamily: 'monospace',
              backgroundColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            );
            break;
          case 'h1':
            newStyle = currentTopStyle.copyWith(fontSize: 22.0, fontWeight: FontWeight.bold);
            break;
          case 'h2':
            newStyle = currentTopStyle.copyWith(fontSize: 18.0, fontWeight: FontWeight.bold);
            break;
          case 'h3':
            newStyle = currentTopStyle.copyWith(fontSize: 16.0, fontWeight: FontWeight.bold);
            break;
          case 'h4':
          case 'h5':
          case 'h6':
            newStyle = currentTopStyle.copyWith(fontSize: 14.0, fontWeight: FontWeight.bold);
            break;
          case 'a':
            newHref = tag.attributes['href'];
            newStyle = currentTopStyle.copyWith(
              color: theme.colorScheme.primary,
              decoration: TextDecoration.underline,
            );
            break;
          case 'font':
          case 'color':
          case 'span':
            final colorAttr = tag.attributes['color'] ?? tag.attributes['value'];
            if (colorAttr != null) {
              final parsedColor = DuiUtils.parseColor(colorAttr);
              if (parsedColor != null) {
                newStyle = currentTopStyle.copyWith(color: parsedColor);
              }
            }
            break;
          case 'li':
            spans.add(TextSpan(
              text: '• ',
              style: currentTopStyle.copyWith(color: theme.colorScheme.primary),
            ));
            break;
        }

        activeStyles.add(newStyle);
        activeHrefs.add(newHref);
      }

      currentIndex = match.end;
    }

    if (currentIndex < rawHtml.length) {
      final text = _decodeEntities(rawHtml.substring(currentIndex));
      if (text.isNotEmpty) {
        spans.add(_buildSpan(
          text,
          _combineStyles(activeStyles),
          activeHrefs.last,
        ));
      }
    }

    return TextSpan(children: spans);
  }

  InlineSpan _buildSpan(String text, TextStyle style, String? href) {
    if (href != null && onLinkTap != null) {
      final recognizer = TapGestureRecognizer()..onTap = () => onLinkTap!(href);
      recognizers?.add(recognizer);
      return TextSpan(text: text, style: style, recognizer: recognizer);
    }
    return TextSpan(text: text, style: style);
  }

  TextStyle _combineStyles(List<TextStyle> styles) {
    return styles.last;
  }

  _HtmlTag _parseTag(String rawName, String rawAttrs) {
    bool isClosing = false;
    String name = rawName.trim().toLowerCase();
    if (name.startsWith('/')) {
      isClosing = true;
      name = name.substring(1);
    }

    final bool isSelfClosing = rawAttrs.trim().endsWith('/');
    final attrs = <String, String>{};

    final attrRegex = RegExp(r'([a-zA-Z0-9_\-]+)\s*=\s*["' "'" r']?([^"' "'" r'\s>]+)["' "'" r']?');
    for (final m in attrRegex.allMatches(rawAttrs)) {
      final key = m.group(1)?.toLowerCase();
      final val = m.group(2);
      if (key != null && val != null) {
        attrs[key] = val;
      }
    }

    return _HtmlTag(
      name: name,
      attributes: attrs,
      isClosing: isClosing,
      isSelfClosing: isSelfClosing,
    );
  }

  String _decodeEntities(String text) {
    return text
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");
  }
}
