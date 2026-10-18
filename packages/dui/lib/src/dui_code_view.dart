import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dui_localizations.dart';

/// 动态 UI (DUI) 代码展示组件。
///
/// 支持等宽字体渲染、行号展示、轻量纯 Dart 语法高亮（JSON、Lua、Dart、SQL、YAML、XML 等）、
/// 水平与垂直滚动以及右上角一键复制到剪贴板。
class DuiCodeView extends StatelessWidget {
  final String text;
  final String language;
  final bool showLineNumbers;
  final bool wrap;
  final double fontSize;
  final bool showCopyButton;
  final double? height;
  final VoidCallback? onCopy;

  const DuiCodeView({
    super.key,
    required this.text,
    this.language = 'plaintext',
    this.showLineNumbers = true,
    this.wrap = false,
    this.fontSize = 12.5,
    this.showCopyButton = true,
    this.height,
    this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final backgroundColor = isDark
        ? const Color(0xFF141926) // 工具箱深色内衬底色
        : const Color(0xFFF2F4F8);

    final baseTextColor =
        isDark ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B);

    final lineNumberColor =
        isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8);

    final borderColor =
        isDark ? const Color(0xFF2D3748) : const Color(0xFFE2E8F0);

    final lines = text.split('\n');
    final totalLines = lines.length;
    final maxLineNumberDigits = totalLines.toString().length;

    final monoStyle = TextStyle(
      fontFamily: 'monospace',
      fontSize: fontSize,
      height: 1.45,
      color: baseTextColor,
    );

    Widget content;
    if (showLineNumbers) {
      final lineSpans = <TextSpan>[];
      for (var i = 1; i <= totalLines; i++) {
        final padded = i.toString().padLeft(maxLineNumberDigits);
        lineSpans.add(TextSpan(text: '$padded\n'));
      }

      final highlightedSpans =
          _highlightCode(text, language, monoStyle, isDark);

      final codeWidget = SelectableText.rich(
        TextSpan(style: monoStyle, children: highlightedSpans),
      );

      final rowContent = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 行号栏
          Container(
            padding: const EdgeInsets.only(right: 12),
            margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(color: borderColor, width: 1.0),
              ),
            ),
            child: Text(
              [
                for (var i = 1; i <= totalLines; i++)
                  i.toString().padLeft(maxLineNumberDigits)
              ].join('\n'),
              textAlign: TextAlign.right,
              style: monoStyle.copyWith(
                color: lineNumberColor,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          // 代码主体
          Expanded(
            child: wrap
                ? codeWidget
                : SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: codeWidget,
                  ),
          ),
        ],
      );

      content = SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: rowContent,
      );
    } else {
      final highlightedSpans =
          _highlightCode(text, language, monoStyle, isDark);
      final codeWidget = SelectableText.rich(
        TextSpan(style: monoStyle, children: highlightedSpans),
      );

      content = SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: wrap
            ? codeWidget
            : SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: codeWidget,
              ),
      );
    }

    Widget root = Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          content,
          if (showCopyButton && text.isNotEmpty)
            Positioned(
              top: 4,
              right: 4,
              child: Material(
                color: Colors.transparent,
                child: IconButton(
                  icon: const Icon(Icons.copy, size: 16),
                  tooltip: DuiLocalizations.of(context).copy,
                  splashRadius: 16,
                  color: lineNumberColor,
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: text));
                    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                      SnackBar(
                        content: Text(
                            DuiLocalizations.of(context).copiedToClipboard),
                        duration: const Duration(milliseconds: 1500),
                      ),
                    );
                    onCopy?.call();
                  },
                ),
              ),
            ),
        ],
      ),
    );

    if (height != null) {
      root = SizedBox(height: height, child: root);
    }

    return root;
  }

  /// 语法高亮分词解析器（纯 Dart 正则分词，轻量且零外部依赖）
  static List<TextSpan> _highlightCode(
    String code,
    String lang,
    TextStyle baseStyle,
    bool isDark,
  ) {
    if (code.isEmpty) return [TextSpan(text: '', style: baseStyle)];

    final normalizedLang = lang.trim().toLowerCase();
    if (normalizedLang == 'plaintext' || normalizedLang.isEmpty) {
      return [TextSpan(text: code, style: baseStyle)];
    }

    // 配色定义
    final keywordColor =
        isDark ? const Color(0xFFC792EA) : const Color(0xFF7C3AED); // 紫色
    final stringColor =
        isDark ? const Color(0xFFC3E88D) : const Color(0xFF16A34A); // 绿色
    final numberColor =
        isDark ? const Color(0xFFF78C6C) : const Color(0xFFEA580C); // 橙色
    final commentColor =
        isDark ? const Color(0xFF6B7280) : const Color(0xFF94A3B8); // 灰色斜体
    final boolColor =
        isDark ? const Color(0xFFFF5370) : const Color(0xFFDC2626); // 红色
    final tagOrKeyColor =
        isDark ? const Color(0xFF82AAFF) : const Color(0xFF2563EB); // 蓝色

    // 正则规则组装
    String? pattern;
    if (normalizedLang == 'json') {
      pattern =
          r'(?<string>"(?:\\.|[^"\\])*")|(?<number>\b-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?\b)|(?<bool>\b(?:true|false|null)\b)|(?<punct>[{}[\],:])';
    } else if (normalizedLang == 'lua') {
      pattern = r'(?<comment>--[^\n]*)|(?<string>"(?:\\.|[^"\\])*"|'
          r"'(?:\\.|[^'\\])*')"
          r'|(?<keyword>\b(?:and|break|do|else|elseif|end|false|for|function|if|in|local|nil|not|or|repeat|return|then|true|until|while)\b)'
          r'|(?<number>\b0x[0-9a-fA-F]+\b|\b\d+(?:\.\d+)?\b)';
    } else if (normalizedLang == 'dart' ||
        normalizedLang == 'javascript' ||
        normalizedLang == 'js') {
      pattern =
          r'(?<comment>//[^\n]*|/\*[\s\S]*?\*/)|(?<string>"(?:\\.|[^"\\])*"|'
          r"'(?:\\.|[^'\\])*')"
          r'|(?<keyword>\b(?:abstract|as|assert|async|await|break|case|catch|class|const|continue|default|deferred|do|dynamic|else|enum|export|extends|extension|external|factory|false|final|finally|for|get|if|implements|import|in|interface|is|late|library|mixin|new|null|operator|part|rethrow|return|set|static|super|switch|sync|this|throw|true|try|typedef|var|void|while|with|yield)\b)'
          r'|(?<number>\b0x[0-9a-fA-F]+\b|\b\d+(?:\.\d+)?\b)';
    } else if (normalizedLang == 'sql') {
      pattern = r'(?<comment>--[^\n]*)|(?<string>\x27[^\x27]*\x27)'
          r'|(?<keyword>\b(?:SELECT|FROM|WHERE|INSERT|INTO|VALUES|UPDATE|SET|DELETE|CREATE|TABLE|DROP|ALTER|ADD|INDEX|JOIN|INNER|LEFT|RIGHT|FULL|ON|GROUP|BY|ORDER|ASC|DESC|LIMIT|OFFSET|HAVING|UNION|ALL|DISTINCT|AS|AND|OR|NOT|IN|BETWEEN|LIKE|IS|NULL|PRIMARY|KEY|FOREIGN|REFERENCES|DEFAULT)\b)'
          r'|(?<number>\b\d+(?:\.\d+)?\b)';
    } else if (normalizedLang == 'yaml' || normalizedLang == 'yml') {
      pattern =
          r'(?<comment>#[^\n]*)|(?<key>^[ \t]*[a-zA-Z0-9_\-\.]+(?=:))|(?<string>"(?:\\.|[^"\\])*"|'
          r"'(?:\\.|[^'\\])*')"
          r'|(?<number>\b\d+(?:\.\d+)?\b)|(?<bool>\b(?:true|false|null|yes|no)\b)';
    } else if (normalizedLang == 'xml' || normalizedLang == 'html') {
      pattern =
          r'(?<comment><!--[\s\S]*?-->)|(?<tag></?[a-zA-Z0-9_\-\:]+)|(?<string>"(?:\\.|[^"\\])*"|'
          r"'(?:\\.|[^'\\])*')"
          r'|(?<bool>\b(?:true|false)\b)';
    }

    if (pattern == null) {
      return [TextSpan(text: code, style: baseStyle)];
    }

    final regExp = RegExp(pattern,
        multiLine: true, caseSensitive: normalizedLang != 'sql');
    final matches = regExp.allMatches(code);
    final spans = <TextSpan>[];
    var lastIndex = 0;

    for (final m in matches) {
      if (m.start > lastIndex) {
        spans.add(TextSpan(
          text: code.substring(lastIndex, m.start),
          style: baseStyle,
        ));
      }

      final matchedText = m.group(0)!;
      TextStyle spanStyle = baseStyle;

      bool hasGroup(String name) =>
          m.groupNames.contains(name) && m.namedGroup(name) != null;

      if (hasGroup('comment')) {
        spanStyle = baseStyle.copyWith(
            color: commentColor, fontStyle: FontStyle.italic);
      } else if (hasGroup('keyword')) {
        spanStyle = baseStyle.copyWith(
            color: keywordColor, fontWeight: FontWeight.w600);
      } else if (hasGroup('string')) {
        // 在 JSON 中，如果是 key 则使用 keyColor
        if (normalizedLang == 'json' &&
            code.substring(m.end).trimLeft().startsWith(':')) {
          spanStyle = baseStyle.copyWith(
              color: tagOrKeyColor, fontWeight: FontWeight.w500);
        } else {
          spanStyle = baseStyle.copyWith(color: stringColor);
        }
      } else if (hasGroup('key') || hasGroup('tag')) {
        spanStyle = baseStyle.copyWith(
            color: tagOrKeyColor, fontWeight: FontWeight.w500);
      } else if (hasGroup('number')) {
        spanStyle = baseStyle.copyWith(color: numberColor);
      } else if (hasGroup('bool')) {
        spanStyle =
            baseStyle.copyWith(color: boolColor, fontWeight: FontWeight.bold);
      }

      spans.add(TextSpan(text: matchedText, style: spanStyle));
      lastIndex = m.end;
    }

    if (lastIndex < code.length) {
      spans.add(TextSpan(
        text: code.substring(lastIndex),
        style: baseStyle,
      ));
    }

    return spans;
  }
}
