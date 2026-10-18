import 'dart:math';
import 'package:flutter/material.dart';
import 'dui_localizations.dart';

/// 动态 UI (DUI) 逐行差异比对组件。
///
/// 采用纯 Dart 实现的 LCS 算法对两段文本进行逐行差异比对，
/// 直观展示新增（绿色）、删除（红色）与未变行，支持双行号与水平滚动。
class DuiDiffView extends StatelessWidget {
  final String oldText;
  final String newText;
  final bool showLineNumbers;
  final double fontSize;
  final bool showSummary;
  final double? height;

  const DuiDiffView({
    super.key,
    required this.oldText,
    required this.newText,
    this.showLineNumbers = true,
    this.fontSize = 12.0,
    this.showSummary = true,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final backgroundColor =
        isDark ? const Color(0xFF141926) : const Color(0xFFF8FAFC);
    final borderColor =
        isDark ? const Color(0xFF2D3748) : const Color(0xFFE2E8F0);
    final baseTextColor =
        isDark ? const Color(0xFFCBD5E1) : const Color(0xFF334155);
    final lineNumberColor =
        isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8);

    // 差异颜色定义
    final addBgColor =
        isDark ? const Color(0x2822C55E) : const Color(0x2816A34A);
    final addTextColor =
        isDark ? const Color(0xFF4ADE80) : const Color(0xFF15803D);

    final delBgColor =
        isDark ? const Color(0x28EF4444) : const Color(0x28DC2626);
    final delTextColor =
        isDark ? const Color(0xFFF87171) : const Color(0xFFB91C1C);

    final diffLines = _computeDiff(oldText, newText);

    var addCount = 0;
    var delCount = 0;
    for (final line in diffLines) {
      if (line.type == _DiffType.add) addCount++;
      if (line.type == _DiffType.delete) delCount++;
    }

    final monoStyle = TextStyle(
      fontFamily: 'monospace',
      fontSize: fontSize,
      height: 1.45,
      color: baseTextColor,
    );

    final Widget listWidget = ListView.builder(
      shrinkWrap: height == null,
      physics: height == null
          ? const NeverScrollableScrollPhysics()
          : const ClampingScrollPhysics(),
      itemCount: diffLines.length,
      itemBuilder: (context, index) {
        final line = diffLines[index];
        final isAdd = line.type == _DiffType.add;
        final isDel = line.type == _DiffType.delete;

        final rowBg =
            isAdd ? addBgColor : (isDel ? delBgColor : Colors.transparent);
        final textColor =
            isAdd ? addTextColor : (isDel ? delTextColor : baseTextColor);
        final prefix = isAdd ? '+' : (isDel ? '-' : ' ');

        return Container(
          color: rowBg,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showLineNumbers) ...[
                // 旧行号
                SizedBox(
                  width: 32,
                  child: Text(
                    line.oldLineNum?.toString() ?? '',
                    textAlign: TextAlign.right,
                    style: monoStyle.copyWith(
                        color: lineNumberColor, fontSize: fontSize * 0.9),
                  ),
                ),
                const SizedBox(width: 6),
                // 新行号
                SizedBox(
                  width: 32,
                  child: Text(
                    line.newLineNum?.toString() ?? '',
                    textAlign: TextAlign.right,
                    style: monoStyle.copyWith(
                        color: lineNumberColor, fontSize: fontSize * 0.9),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              // 符号前缀 (+ / - / 空格)
              SizedBox(
                width: 14,
                child: Text(
                  prefix,
                  style: monoStyle.copyWith(
                    color: textColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              // 文本主体（允许水平滚动）
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Text(
                    line.text,
                    style: monoStyle.copyWith(color: textColor),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    final Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showSummary)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E2638) : const Color(0xFFEDF2F7),
              border: Border(bottom: BorderSide(color: borderColor)),
            ),
            child: Row(
              children: [
                const Icon(Icons.compare_arrows, size: 16),
                const SizedBox(width: 8),
                Text(
                  DuiLocalizations.of(context).diffView,
                  style: theme.textTheme.labelMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Text(
                  '+$addCount',
                  style: TextStyle(
                    color: addTextColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '-$delCount',
                  style: TextStyle(
                    color: delTextColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
        if (height != null) Expanded(child: listWidget) else listWidget,
      ],
    );

    Widget root = Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: content,
    );

    if (height != null) {
      root = SizedBox(height: height, child: root);
    }

    return root;
  }

  /// 纯 Dart LCS 逐行对比算法
  static List<_DiffLine> _computeDiff(String oldText, String newText) {
    final oldLines = oldText.isEmpty ? <String>[] : oldText.split('\n');
    final newLines = newText.isEmpty ? <String>[] : newText.split('\n');

    final m = oldLines.length;
    final n = newLines.length;

    // 前缀相同行快速跳过
    var prefix = 0;
    while (prefix < m && prefix < n && oldLines[prefix] == newLines[prefix]) {
      prefix++;
    }

    // 后缀相同行快速跳过
    var suffix = 0;
    while (suffix < (m - prefix) &&
        suffix < (n - prefix) &&
        oldLines[m - 1 - suffix] == newLines[n - 1 - suffix]) {
      suffix++;
    }

    final midOld = oldLines.sublist(prefix, m - suffix);
    final midNew = newLines.sublist(prefix, n - suffix);

    // LCS 动态规划求解核心不同区域
    final dp = List.generate(
      midOld.length + 1,
      (_) => List<int>.filled(midNew.length + 1, 0),
    );

    for (var i = 1; i <= midOld.length; i++) {
      for (var j = 1; j <= midNew.length; j++) {
        if (midOld[i - 1] == midNew[j - 1]) {
          dp[i][j] = dp[i - 1][j - 1] + 1;
        } else {
          dp[i][j] = max(dp[i - 1][j], dp[i][j - 1]);
        }
      }
    }

    // 回溯构建差异操作
    final midDiff = <_DiffLine>[];
    var i = midOld.length;
    var j = midNew.length;

    while (i > 0 || j > 0) {
      if (i > 0 && j > 0 && midOld[i - 1] == midNew[j - 1]) {
        midDiff.add(_DiffLine(
          type: _DiffType.keep,
          text: midOld[i - 1],
        ));
        i--;
        j--;
      } else if (j > 0 && (i == 0 || dp[i][j - 1] >= dp[i - 1][j])) {
        midDiff.add(_DiffLine(
          type: _DiffType.add,
          text: midNew[j - 1],
        ));
        j--;
      } else if (i > 0 && (j == 0 || dp[i][j - 1] < dp[i - 1][j])) {
        midDiff.add(_DiffLine(
          type: _DiffType.delete,
          text: midOld[i - 1],
        ));
        i--;
      }
    }

    final reversedMid = midDiff.reversed.toList();

    // 组合结果并填充行号
    final result = <_DiffLine>[];
    var oldNum = 1;
    var newNum = 1;

    // 前缀
    for (var k = 0; k < prefix; k++) {
      result.add(_DiffLine(
        type: _DiffType.keep,
        text: oldLines[k],
        oldLineNum: oldNum++,
        newLineNum: newNum++,
      ));
    }

    // 中间差异
    for (final line in reversedMid) {
      if (line.type == _DiffType.keep) {
        result.add(_DiffLine(
          type: _DiffType.keep,
          text: line.text,
          oldLineNum: oldNum++,
          newLineNum: newNum++,
        ));
      } else if (line.type == _DiffType.delete) {
        result.add(_DiffLine(
          type: _DiffType.delete,
          text: line.text,
          oldLineNum: oldNum++,
          newLineNum: null,
        ));
      } else if (line.type == _DiffType.add) {
        result.add(_DiffLine(
          type: _DiffType.add,
          text: line.text,
          oldLineNum: null,
          newLineNum: newNum++,
        ));
      }
    }

    // 后缀
    for (var k = m - suffix; k < m; k++) {
      result.add(_DiffLine(
        type: _DiffType.keep,
        text: oldLines[k],
        oldLineNum: oldNum++,
        newLineNum: newNum++,
      ));
    }

    return result;
  }
}

enum _DiffType { keep, add, delete }

class _DiffLine {
  final _DiffType type;
  final String text;
  final int? oldLineNum;
  final int? newLineNum;

  _DiffLine({
    required this.type,
    required this.text,
    this.oldLineNum,
    this.newLineNum,
  });
}
