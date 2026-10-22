import 'package:flutter/material.dart';

import '../theme/app_semantic_colors.dart';
import '../theme/app_tokens.dart';

/// 统一轻量反馈（SnackBar）。
///
/// 全站提示不再各自 new SnackBar：统一浮动样式、图标、时长与"先清队列"
/// 的行为，避免快速连点时提示排队堆叠、遮挡底部操作。
class AppSnack {
  AppSnack._();

  static const Duration _short = Duration(seconds: 2);
  static const Duration _long = Duration(seconds: 4);

  static void info(BuildContext context, String message) {
    _show(context, message, Icons.info_outline_rounded,
        Theme.of(context).colorScheme.primary);
  }

  static void success(BuildContext context, String message) {
    _show(context, message, Icons.check_circle_outline_rounded,
        context.appColors.success);
  }

  static void warning(BuildContext context, String message) {
    _show(context, message, Icons.warning_amber_rounded,
        context.appColors.warning);
  }

  static void error(BuildContext context, String message) {
    _show(context, message, Icons.error_outline_rounded,
        Theme.of(context).colorScheme.error,
        duration: _long);
  }

  static void _show(
    BuildContext context,
    String message,
    IconData icon,
    Color accent, {
    Duration duration = _short,
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    // 快速连点时先清空队列，防止提示相互排队导致延迟消失
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        duration: duration,
        content: Row(
          children: [
            Icon(icon, size: 18, color: accent),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }
}
