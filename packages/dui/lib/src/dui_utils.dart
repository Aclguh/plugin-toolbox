import 'package:flutter/material.dart';

class DuiUtils {
  /// 图标名称查找表：插件 JSON 中的图标名 -> Material IconData
  static const Map<String, IconData> _iconTable = {
    'code': Icons.code,
    'qr_code': Icons.qr_code,
    'qr_code_scanner': Icons.qr_code_scanner,
    'phone_android': Icons.phone_android,
    'arrow_downward': Icons.arrow_downward,
    'arrow_upward': Icons.arrow_upward,
    'swap_vert': Icons.swap_vert,
    'content_copy': Icons.content_copy,
    'settings': Icons.settings,
    'delete_outline': Icons.delete_outline,
    'search': Icons.search,
    'check': Icons.check,
  };

  /// M3 TextStyle 查找表（样式名 -> TextTheme 取值闭包），
  /// 以 static final 声明，闭包仅在类加载时创建一次
  static final Map<String, TextStyle? Function(TextTheme)> _textStyleTable = {
    'displayLarge': (t) => t.displayLarge,
    'displayMedium': (t) => t.displayMedium,
    'displaySmall': (t) => t.displaySmall,
    'headlineLarge': (t) => t.headlineLarge,
    'headlineMedium': (t) => t.headlineMedium,
    'headlineSmall': (t) => t.headlineSmall,
    'titleLarge': (t) => t.titleLarge,
    'titleMedium': (t) => t.titleMedium,
    'titleSmall': (t) => t.titleSmall,
    'bodyLarge': (t) => t.bodyLarge,
    'bodyMedium': (t) => t.bodyMedium,
    'bodySmall': (t) => t.bodySmall,
    'labelLarge': (t) => t.labelLarge,
  };

  /// 将字符串名称转换为 Material IconData
  static IconData parseIcon(String? iconName) {
    if (iconName == null) return Icons.extension;
    return _iconTable[iconName.toLowerCase()] ?? Icons.extension;
  }

  /// 解析 M3 TextStyle
  static TextStyle? parseTextStyle(BuildContext context, String? styleName) {
    if (styleName == null) return null;
    final accessor = _textStyleTable[styleName];
    if (accessor == null) return null;
    return accessor(Theme.of(context).textTheme);
  }

  /// 解析 EdgeInsets；数值与字符串数字统一容错
  static EdgeInsets parsePadding(dynamic paddingVal) {
    if (paddingVal == null) return EdgeInsets.zero;
    if (paddingVal is num) return EdgeInsets.all(paddingVal.toDouble());
    if (paddingVal is String) {
      final all = tryDouble(paddingVal);
      return all != null ? EdgeInsets.all(all) : EdgeInsets.zero;
    }
    if (paddingVal is Map) {
      return EdgeInsets.only(
        left: tryDouble(paddingVal['left']) ?? 0,
        top: tryDouble(paddingVal['top']) ?? 0,
        right: tryDouble(paddingVal['right']) ?? 0,
        bottom: tryDouble(paddingVal['bottom']) ?? 0,
      );
    }
    return EdgeInsets.zero;
  }

  /// 安全数值解析：统一容忍 num / String / null 三种输入。
  ///
  /// 第三方插件的 JSON 中数值常被误写为字符串（如 "100"），
  /// 直接 `as num?` 强转会抛 TypeError 导致插件页面崩溃。
  static double? tryDouble(dynamic val) {
    if (val is num) return val.toDouble();
    if (val is String) return double.tryParse(val.trim());
    return null;
  }

  /// 安全整型解析：容忍 num / String / null
  static int? tryInt(dynamic val) {
    if (val is num) return val.toInt();
    if (val is String) return int.tryParse(val.trim());
    return null;
  }

  /// 安全布尔解析：容忍 bool / String（"true"）/ num（非零为真）/ null
  static bool tryBool(dynamic val, {bool fallback = false}) {
    if (val is bool) return val;
    if (val is num) return val != 0;
    if (val is String) {
      final s = val.trim().toLowerCase();
      if (s == 'true') return true;
      if (s == 'false') return false;
    }
    return fallback;
  }
}
