import 'package:flutter/material.dart';

/// 品牌字体层级。
///
/// 只负责字号 / 字重 / 行高 / 字距（即"层级"），颜色由主题统一注入：
/// 这样亮暗两套主题共用同一套层级，避免两处各写一份字号导致漂移。
///
/// 尺度约定（字号 -> 用途）：
/// - 28 / 22：页面主标题、空状态大标题
/// - 19 / 17：卡片组标题、弹窗标题
/// - 15 / 14：正文、列表主文本
/// - 13 / 12：辅助说明、元信息
/// - 11：极弱信息（版本号、脚注）
class AppTypography {
  AppTypography._();

  /// 正文与标题统一字族：交由系统字体（中文优先苹方 / 思源），
  /// 显式声明 null 以复用平台最佳可读性字体。
  static const String? fontFamily = null;

  static const double _tight = -0.2;
  static const double _normal = 0.0;
  static const double _wide = 0.2;

  static TextTheme textTheme() {
    return const TextTheme(
      // 超大标题：空状态、错误页主标题
      displaySmall: TextStyle(
        fontFamily: fontFamily,
        fontSize: 26,
        fontWeight: FontWeight.w700,
        height: 1.2,
        letterSpacing: -0.6,
      ),
      headlineSmall: TextStyle(
        fontFamily: fontFamily,
        fontSize: 22,
        fontWeight: FontWeight.w700,
        height: 1.25,
        letterSpacing: -0.4,
      ),
      // 页面 / 弹窗标题
      titleLarge: TextStyle(
        fontFamily: fontFamily,
        fontSize: 19,
        fontWeight: FontWeight.w700,
        height: 1.3,
        letterSpacing: _tight,
      ),
      titleMedium: TextStyle(
        fontFamily: fontFamily,
        fontSize: 16,
        fontWeight: FontWeight.w600,
        height: 1.35,
        letterSpacing: -0.1,
      ),
      titleSmall: TextStyle(
        fontFamily: fontFamily,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        height: 1.35,
        letterSpacing: _normal,
      ),
      // 正文
      bodyLarge: TextStyle(
        fontFamily: fontFamily,
        fontSize: 15,
        fontWeight: FontWeight.w400,
        height: 1.5,
        letterSpacing: _normal,
      ),
      bodyMedium: TextStyle(
        fontFamily: fontFamily,
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.45,
        letterSpacing: _normal,
      ),
      bodySmall: TextStyle(
        fontFamily: fontFamily,
        fontSize: 12,
        fontWeight: FontWeight.w400,
        height: 1.4,
        letterSpacing: 0.1,
      ),
      // 按钮 / 标签
      labelLarge: TextStyle(
        fontFamily: fontFamily,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        height: 1.2,
        letterSpacing: 0.1,
      ),
      labelMedium: TextStyle(
        fontFamily: fontFamily,
        fontSize: 12,
        fontWeight: FontWeight.w600,
        height: 1.2,
        letterSpacing: _wide,
      ),
      labelSmall: TextStyle(
        fontFamily: fontFamily,
        fontSize: 11,
        fontWeight: FontWeight.w500,
        height: 1.2,
        letterSpacing: 0.3,
      ),
    );
  }

  /// 等宽字族（协议文本、日志、代码等需要对齐的场景）
  static const String monospace = 'monospace';
}
