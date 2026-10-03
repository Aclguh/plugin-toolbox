import 'package:flutter/material.dart';

/// 软件默认品牌主题调色板（提取自应用矢量图标 SVG）
class AppColorSchemes {
  AppColorSchemes._();

  /// 品牌主背景色（SVG 背景渐变主导色）
  static const Color brandBackground = Color(0xFF26366A);

  /// 品牌文字主要字体色（SVG 装饰光圈与文字强调色）
  static const Color brandFont = Color(0xFFB4C9FF);

  /// SVG 背景深色暗部
  static const Color brandDeepNavy = Color(0xFF111936);

  /// SVG 内槽凹陷背景（卡片容器底色）
  static const Color brandInnerNavy = Color(0xFF1B2445);

  /// SVG 把手与锁扣主提色（亮丽的靛青天蓝）
  static const Color brandPeriwinkle = Color(0xFF788CFF);

  /// SVG 薄荷青光圈与插件色
  static const Color brandMint = Color(0xFF31D9D0);

  /// SVG 珊瑚粉光圈与插件色
  static const Color brandCoral = Color(0xFFFF9D72);

  /// SVG 琥珀橙插件色
  static const Color brandAmber = Color(0xFFFFD478);

  /// SVG 浅色外壳亮银蓝
  static const Color brandCaseLight = Color(0xFFCAD9F8);

  /// 默认品牌深色主题方案（#26366A 为背景，#B4C9FF 为字体）
  static const ColorScheme darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: brandPeriwinkle,
    onPrimary: Color(0xFF0C1638),
    primaryContainer: Color(0xFF374A82),
    onPrimaryContainer: Color(0xFFDCE4FF),
    secondary: brandMint,
    onSecondary: Color(0xFF003734),
    secondaryContainer: Color(0xFF00504B),
    onSecondaryContainer: Color(0xFF72F5EC),
    tertiary: brandCoral,
    onTertiary: Color(0xFF552100),
    tertiaryContainer: Color(0xFF783100),
    onTertiaryContainer: Color(0xFFFFDBCF),
    error: Color(0xFFFFB4AB),
    onError: Color(0xFF690005),
    errorContainer: Color(0xFF93000A),
    onErrorContainer: Color(0xFFFFDAD6),
    surface: brandBackground, // #26366A 为背景
    onSurface: brandFont, // #B4C9FF 为字体
    onSurfaceVariant: Color(0xFF99B2E0), // 次级文字调亮至 #99B2E0，对卡片底色 #1B2445 对比度达 7.07:1 (WCAG AAA)
    surfaceContainerLowest: brandDeepNavy,
    surfaceContainerLow: brandInnerNavy, // 工具箱内槽卡片色
    surfaceContainer: Color(0xFF202B54),
    surfaceContainerHigh: Color(0xFF2D3C72),
    surfaceContainerHighest: Color(0xFF3A4D8B),
    outline: Color(0xFF6B7FAE),
    outlineVariant: Color(0xFF384B7E),
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: Color(0xFFEAF1FF),
    onInverseSurface: brandInnerNavy,
    inversePrimary: brandBackground,
  );

  /// 清新浅色主题方案（基于 SVG 工具箱银白外壳与蓝系提取）
  static const ColorScheme lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: brandBackground,
    onPrimary: Colors.white,
    primaryContainer: brandCaseLight,
    onPrimaryContainer: brandDeepNavy,
    secondary: Color(0xFF006A63),
    onSecondary: Colors.white,
    secondaryContainer: Color(0xFFD0F8F4),
    onSecondaryContainer: Color(0xFF00201D),
    tertiary: Color(0xFF9E431B),
    onTertiary: Colors.white,
    tertiaryContainer: Color(0xFFFFDBD0),
    onTertiaryContainer: Color(0xFF3B1000),
    error: Color(0xFFBA1A1A),
    onError: Colors.white,
    errorContainer: Color(0xFFFFDAD6),
    onErrorContainer: Color(0xFF410002),
    surface: Color(0xFFF6F9FF),
    onSurface: Color(0xFF131A33),
    onSurfaceVariant: Color(0xFF434E70),
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: Color(0xFFEEF3FC),
    surfaceContainer: Color(0xFFE5EDF9),
    surfaceContainerHigh: Color(0xFFDCE6F5),
    surfaceContainerHighest: brandCaseLight,
    outline: Color(0xFF7581A4),
    outlineVariant: Color(0xFFB5C1DE),
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: brandInnerNavy,
    onInverseSurface: Color(0xFFEAF1FF),
    inversePrimary: brandFont,
  );
}
