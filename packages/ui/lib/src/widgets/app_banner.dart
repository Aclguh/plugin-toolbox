import 'package:flutter/material.dart';

import '../theme/app_semantic_colors.dart';
import '../theme/app_tokens.dart';

/// 提示条语义档位
enum AppBannerTone { info, success, warning, danger }

/// 行内提示条：用于页面顶部的操作说明、风险提醒与结果摘要。
///
/// 与 SnackBar（瞬时反馈）互补，这里承载"需要持续可见"的信息，
/// 视觉上以低饱和底色 + 单侧图标 + 可选动作按钮组成，避免抢主内容。
class AppBanner extends StatelessWidget {
  const AppBanner({
    super.key,
    required this.message,
    this.title,
    this.tone = AppBannerTone.info,
    this.icon,
    this.action,
  });

  final String message;
  final String? title;
  final AppBannerTone tone;
  final IconData? icon;
  final Widget? action;

  Color _accent(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final semantic = context.appColors;
    switch (tone) {
      case AppBannerTone.info:
        return semantic.info;
      case AppBannerTone.success:
        return semantic.success;
      case AppBannerTone.warning:
        return semantic.warning;
      case AppBannerTone.danger:
        return scheme.error;
    }
  }

  IconData get _defaultIcon {
    switch (tone) {
      case AppBannerTone.info:
        return Icons.info_outline_rounded;
      case AppBannerTone.success:
        return Icons.check_circle_outline_rounded;
      case AppBannerTone.warning:
        return Icons.warning_amber_rounded;
      case AppBannerTone.danger:
        return Icons.error_outline_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = _accent(context);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm + 2,
      ),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: accent.withValues(alpha: 0.32)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon ?? _defaultIcon, size: 18, color: accent),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  Text(
                    title!,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: accent,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                ],
                Text(
                  message,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (action != null) ...[
            const SizedBox(width: AppSpacing.sm),
            action!,
          ],
        ],
      ),
    );
  }
}
