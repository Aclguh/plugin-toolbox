import 'package:flutter/material.dart';

import '../theme/app_semantic_colors.dart';
import '../theme/app_tokens.dart';

/// 徽标语义色档位
enum AppBadgeTone { neutral, primary, success, warning, danger, info }

/// 统一的小型状态徽标（胶囊形）。
///
/// 用于"动态 / 敏感 / 可更新 / 已安装"等状态标识，
/// 所有页面共享同一套尺寸、圆角与配色规则，避免各自用 Container 拼样式。
class AppBadge extends StatelessWidget {
  const AppBadge({
    super.key,
    required this.label,
    this.tone = AppBadgeTone.neutral,
    this.icon,
    this.dense = false,
  });

  final String label;
  final AppBadgeTone tone;
  final IconData? icon;

  /// 紧凑模式：更小的字号与内边距，用于列表内联徽标
  final bool dense;

  Color _foreground(ColorScheme scheme, AppSemanticColors semantic) {
    switch (tone) {
      case AppBadgeTone.neutral:
        return scheme.onSurfaceVariant;
      case AppBadgeTone.primary:
        return scheme.primary;
      case AppBadgeTone.success:
        return semantic.success;
      case AppBadgeTone.warning:
        return semantic.warning;
      case AppBadgeTone.danger:
        return scheme.error;
      case AppBadgeTone.info:
        return semantic.info;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final semantic = context.appColors;
    final foreground = _foreground(scheme, semantic);
    final fontSize = dense ? 10.0 : 11.0;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? AppSpacing.sm - 2 : AppSpacing.sm,
        vertical: dense ? 1.5 : AppSpacing.xxs + 1,
      ),
      decoration: BoxDecoration(
        color: foreground.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: foreground.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: fontSize + 2, color: foreground),
            const SizedBox(width: AppSpacing.xs),
          ],
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              color: foreground,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}
