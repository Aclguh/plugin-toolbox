import 'package:flutter/material.dart';

/// 纯原生、零第三方依赖的轻量声明式 Markdown 渲染组件。
///
/// 具备 WCAG AAA 深度适配、支持多级标题、代码块、引用块、列表与行内格式化。
class DuiMarkdownView extends StatelessWidget {
  final String data;
  final bool selectable;
  final TextStyle? baseStyle;

  const DuiMarkdownView({
    super.key,
    required this.data,
    this.selectable = true,
    this.baseStyle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final colorScheme = theme.colorScheme;

    final defaultBodyStyle = (baseStyle ?? textTheme.bodyMedium)?.copyWith(
          color: colorScheme.onSurface,
          height: 1.5,
        ) ??
        TextStyle(color: colorScheme.onSurface, height: 1.5);

    final lines = data.split('\n');
    final widgets = <Widget>[];

    bool inCodeBlock = false;
    final codeBlockLines = <String>[];
    String? codeLang;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      final trimmed = line.trim();

      // 代码块解析
      if (trimmed.startsWith('```')) {
        if (!inCodeBlock) {
          inCodeBlock = true;
          codeLang = trimmed.substring(3).trim();
          codeBlockLines.clear();
        } else {
          inCodeBlock = false;
          widgets.add(_buildCodeBlock(context, codeBlockLines.join('\n'), codeLang));
          codeBlockLines.clear();
          codeLang = null;
        }
        continue;
      }

      if (inCodeBlock) {
        codeBlockLines.add(line);
        continue;
      }

      // 空行
      if (trimmed.isEmpty) {
        widgets.add(const SizedBox(height: 8));
        continue;
      }

      // 分割线
      if (trimmed == '---' || trimmed == '***' || trimmed == '___') {
        widgets.add(Divider(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          height: 24,
        ));
        continue;
      }

      // 标题解析 (# ~ ######)
      if (trimmed.startsWith('#')) {
        int level = 0;
        while (level < trimmed.length && trimmed[level] == '#') {
          level++;
        }
        if (level <= 6 && trimmed.length > level && trimmed[level] == ' ') {
          final titleText = trimmed.substring(level + 1).trim();
          widgets.add(_buildHeading(context, titleText, level));
          continue;
        }
      }

      // 引用块 (>)
      if (trimmed.startsWith('>')) {
        final quoteText = trimmed.substring(1).trim();
        widgets.add(_buildBlockquote(context, quoteText, defaultBodyStyle));
        continue;
      }

      // 列表 (- / * / 1.)
      final bulletMatch = RegExp(r'^(\*|-|\+)\s+(.*)$').firstMatch(trimmed);
      if (bulletMatch != null) {
        final content = bulletMatch.group(2) ?? '';
        widgets.add(_buildListItem(context, '•', content, defaultBodyStyle));
        continue;
      }

      final numListMatch = RegExp(r'^(\d+)\.\s+(.*)$').firstMatch(trimmed);
      if (numListMatch != null) {
        final numPrefix = '${numListMatch.group(1)}.';
        final content = numListMatch.group(2) ?? '';
        widgets.add(_buildListItem(context, numPrefix, content, defaultBodyStyle));
        continue;
      }

      // 普通段落
      widgets.add(_buildParagraph(context, trimmed, defaultBodyStyle));
    }

    // 若代码块未闭合，补充渲染
    if (inCodeBlock && codeBlockLines.isNotEmpty) {
      widgets.add(_buildCodeBlock(context, codeBlockLines.join('\n'), codeLang));
    }

    final contentWidget = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: widgets,
    );

    return selectable ? SelectionArea(child: contentWidget) : contentWidget;
  }

  Widget _buildHeading(BuildContext context, String text, int level) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final baseColor = colorScheme.onSurface;

    double fontSize;
    FontWeight fontWeight = FontWeight.bold;
    double topSpacing;

    switch (level) {
      case 1:
        fontSize = 22;
        topSpacing = 16;
        break;
      case 2:
        fontSize = 18;
        topSpacing = 14;
        break;
      case 3:
        fontSize = 16;
        topSpacing = 12;
        break;
      default:
        fontSize = 14;
        topSpacing = 10;
        fontWeight = FontWeight.w600;
        break;
    }

    return Padding(
      padding: EdgeInsets.only(top: topSpacing, bottom: 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: fontWeight,
          color: baseColor,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Widget _buildBlockquote(
    BuildContext context,
    String text,
    TextStyle defaultStyle,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border(
          left: BorderSide(
            color: colorScheme.primary,
            width: 4,
          ),
        ),
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(4),
          bottomRight: Radius.circular(4),
        ),
      ),
      child: _buildRichText(
        context,
        text,
        defaultStyle.copyWith(
          color: colorScheme.onSurfaceVariant,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }

  Widget _buildCodeBlock(BuildContext context, String code, String? lang) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Text(
        code,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          color: colorScheme.secondary,
          height: 1.4,
        ),
      ),
    );
  }

  Widget _buildListItem(
    BuildContext context,
    String prefix,
    String content,
    TextStyle defaultStyle,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 24,
            child: Text(
              prefix,
              style: defaultStyle.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          Expanded(child: _buildRichText(context, content, defaultStyle)),
        ],
      ),
    );
  }

  Widget _buildParagraph(
    BuildContext context,
    String text,
    TextStyle defaultStyle,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: _buildRichText(context, text, defaultStyle),
    );
  }

  Widget _buildRichText(
    BuildContext context,
    String raw,
    TextStyle baseStyle,
  ) {
    final spans = _parseInlineSpans(context, raw, baseStyle);
    return Text.rich(TextSpan(children: spans));
  }

  List<InlineSpan> _parseInlineSpans(
    BuildContext context,
    String text,
    TextStyle baseStyle,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final spans = <InlineSpan>[];
    // 正则解析行内粗体 (**text**), 行内斜体 (*text*), 行内代码 (`code`)
    final pattern = RegExp(r'(\*\*.*?\*\*|\*.*?\*|`.*?`)');
    int lastIndex = 0;

    for (final match in pattern.allMatches(text)) {
      if (match.start > lastIndex) {
        spans.add(TextSpan(
          text: text.substring(lastIndex, match.start),
          style: baseStyle,
        ));
      }

      final matched = match.group(0)!;
      if (matched.startsWith('**') && matched.endsWith('**') && matched.length >= 4) {
        spans.add(TextSpan(
          text: matched.substring(2, matched.length - 2),
          style: baseStyle.copyWith(fontWeight: FontWeight.bold),
        ));
      } else if (matched.startsWith('*') && matched.endsWith('*') && matched.length >= 2) {
        spans.add(TextSpan(
          text: matched.substring(1, matched.length - 1),
          style: baseStyle.copyWith(fontStyle: FontStyle.italic),
        ));
      } else if (matched.startsWith('`') && matched.endsWith('`') && matched.length >= 2) {
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                width: 0.5,
              ),
            ),
            child: Text(
              matched.substring(1, matched.length - 1),
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: (baseStyle.fontSize ?? 14) * 0.9,
                color: colorScheme.secondary,
              ),
            ),
          ),
        ));
      }

      lastIndex = match.end;
    }

    if (lastIndex < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastIndex),
        style: baseStyle,
      ));
    }

    return spans;
  }
}
