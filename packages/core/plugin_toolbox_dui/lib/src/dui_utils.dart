import 'package:flutter/material.dart';

class DuiUtils {
  /// 将字符串名称转换为 Material IconData
  static IconData parseIcon(String? iconName) {
    if (iconName == null) return Icons.extension;
    switch (iconName.toLowerCase()) {
      case 'code': return Icons.code;
      case 'qr_code': return Icons.qr_code;
      case 'qr_code_scanner': return Icons.qr_code_scanner;
      case 'phone_android': return Icons.phone_android;
      case 'arrow_downward': return Icons.arrow_downward;
      case 'arrow_upward': return Icons.arrow_upward;
      case 'swap_vert': return Icons.swap_vert;
      case 'content_copy': return Icons.content_copy;
      case 'settings': return Icons.settings;
      case 'delete_outline': return Icons.delete_outline;
      case 'search': return Icons.search;
      case 'check': return Icons.check;
      default: return Icons.extension;
    }
  }

  /// 解析 M3 TextStyle
  static TextStyle? parseTextStyle(BuildContext context, String? styleName) {
    if (styleName == null) return null;
    final textTheme = Theme.of(context).textTheme;
    switch (styleName) {
      case 'displayLarge': return textTheme.displayLarge;
      case 'displayMedium': return textTheme.displayMedium;
      case 'displaySmall': return textTheme.displaySmall;
      case 'headlineLarge': return textTheme.headlineLarge;
      case 'headlineMedium': return textTheme.headlineMedium;
      case 'headlineSmall': return textTheme.headlineSmall;
      case 'titleLarge': return textTheme.titleLarge;
      case 'titleMedium': return textTheme.titleMedium;
      case 'titleSmall': return textTheme.titleSmall;
      case 'bodyLarge': return textTheme.bodyLarge;
      case 'bodyMedium': return textTheme.bodyMedium;
      case 'bodySmall': return textTheme.bodySmall;
      case 'labelLarge': return textTheme.labelLarge;
      default: return null;
    }
  }

  /// 解析 EdgeInsets
  static EdgeInsets parsePadding(dynamic paddingVal) {
    if (paddingVal == null) return EdgeInsets.zero;
    if (paddingVal is num) return EdgeInsets.all(paddingVal.toDouble());
    if (paddingVal is Map) {
      return EdgeInsets.only(
        left: (paddingVal['left'] as num?)?.toDouble() ?? 0,
        top: (paddingVal['top'] as num?)?.toDouble() ?? 0,
        right: (paddingVal['right'] as num?)?.toDouble() ?? 0,
        bottom: (paddingVal['bottom'] as num?)?.toDouble() ?? 0,
      );
    }
    return EdgeInsets.zero;
  }
}
