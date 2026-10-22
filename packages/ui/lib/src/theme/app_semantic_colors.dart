import 'package:flutter/material.dart';

/// 语义色扩展：Material 3 只提供 error 语义，缺少"成功 / 警告 / 信息"，
/// 各页面此前各自硬编码红绿黄，导致同一语义在不同页面颜色不一。
///
/// 这里以 [ThemeExtension] 形式挂到主题上，随亮暗主题自动切换，
/// 页面统一通过 `context.appColors.success` 一类入口取色。
@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  const AppSemanticColors({
    required this.success,
    required this.onSuccess,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.warning,
    required this.onWarning,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.info,
    required this.onInfo,
    required this.infoContainer,
    required this.onInfoContainer,
  });

  final Color success;
  final Color onSuccess;
  final Color successContainer;
  final Color onSuccessContainer;

  final Color warning;
  final Color onWarning;
  final Color warningContainer;
  final Color onWarningContainer;

  final Color info;
  final Color onInfo;
  final Color infoContainer;
  final Color onInfoContainer;

  /// 品牌深色主题下的语义色（取自图标 SVG 的薄荷青 / 琥珀橙 / 冰蓝）
  static const AppSemanticColors dark = AppSemanticColors(
    success: Color(0xFF31D9D0),
    onSuccess: Color(0xFF00322F),
    successContainer: Color(0xFF1C4A4C),
    onSuccessContainer: Color(0xFF9CF7F1),
    warning: Color(0xFFFFD478),
    onWarning: Color(0xFF3A2A00),
    warningContainer: Color(0xFF4A3A12),
    onWarningContainer: Color(0xFFFFE7B2),
    info: Color(0xFF9FC0FF),
    onInfo: Color(0xFF0C1638),
    infoContainer: Color(0xFF2A3A6B),
    onInfoContainer: Color(0xFFDCE4FF),
  );

  /// 清新浅色主题下的语义色
  static const AppSemanticColors light = AppSemanticColors(
    success: Color(0xFF00695F),
    onSuccess: Colors.white,
    successContainer: Color(0xFFC6F2EC),
    onSuccessContainer: Color(0xFF00201D),
    warning: Color(0xFF8A5A00),
    onWarning: Colors.white,
    warningContainer: Color(0xFFFFE7BC),
    onWarningContainer: Color(0xFF2C1C00),
    info: Color(0xFF26366A),
    onInfo: Colors.white,
    infoContainer: Color(0xFFDCE4FF),
    onInfoContainer: Color(0xFF111936),
  );

  static AppSemanticColors of(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Theme.of(context).extension<AppSemanticColors>() ??
        (brightness == Brightness.dark ? dark : light);
  }

  @override
  AppSemanticColors copyWith({
    Color? success,
    Color? onSuccess,
    Color? successContainer,
    Color? onSuccessContainer,
    Color? warning,
    Color? onWarning,
    Color? warningContainer,
    Color? onWarningContainer,
    Color? info,
    Color? onInfo,
    Color? infoContainer,
    Color? onInfoContainer,
  }) {
    return AppSemanticColors(
      success: success ?? this.success,
      onSuccess: onSuccess ?? this.onSuccess,
      successContainer: successContainer ?? this.successContainer,
      onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
      warning: warning ?? this.warning,
      onWarning: onWarning ?? this.onWarning,
      warningContainer: warningContainer ?? this.warningContainer,
      onWarningContainer: onWarningContainer ?? this.onWarningContainer,
      info: info ?? this.info,
      onInfo: onInfo ?? this.onInfo,
      infoContainer: infoContainer ?? this.infoContainer,
      onInfoContainer: onInfoContainer ?? this.onInfoContainer,
    );
  }

  @override
  AppSemanticColors lerp(ThemeExtension<AppSemanticColors>? other, double t) {
    if (other is! AppSemanticColors) return this;
    return AppSemanticColors(
      success: Color.lerp(success, other.success, t)!,
      onSuccess: Color.lerp(onSuccess, other.onSuccess, t)!,
      successContainer:
          Color.lerp(successContainer, other.successContainer, t)!,
      onSuccessContainer:
          Color.lerp(onSuccessContainer, other.onSuccessContainer, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      onWarning: Color.lerp(onWarning, other.onWarning, t)!,
      warningContainer:
          Color.lerp(warningContainer, other.warningContainer, t)!,
      onWarningContainer:
          Color.lerp(onWarningContainer, other.onWarningContainer, t)!,
      info: Color.lerp(info, other.info, t)!,
      onInfo: Color.lerp(onInfo, other.onInfo, t)!,
      infoContainer: Color.lerp(infoContainer, other.infoContainer, t)!,
      onInfoContainer: Color.lerp(onInfoContainer, other.onInfoContainer, t)!,
    );
  }
}

/// 语义色的上下文快捷入口：`context.appColors.warning`
extension AppSemanticColorsContext on BuildContext {
  AppSemanticColors get appColors => AppSemanticColors.of(this);
}
