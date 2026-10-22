import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// 统一空状态：图标光晕 + 主标题 + 说明 + 主/次操作。
///
/// 内容整体可滚动，超小屏（如横屏手机）也不会出现溢出；
/// 所有空态（无插件、无搜索结果、路由不存在、插件停用）共用此组件，
/// 保证"没有内容时"的页面依然符合品牌视觉。
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.secondaryAction,
    this.iconColor,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  final Widget? secondaryAction;

  /// 图标主色，默认取主题 primary
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = iconColor ?? scheme.primary;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _IconHalo(icon: icon, color: accent),
              const SizedBox(height: AppSpacing.xl),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: scheme.onSurface,
                ),
              ),
              if (message != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
              ],
              if (action != null) ...[
                const SizedBox(height: AppSpacing.xl),
                action!,
              ],
              if (secondaryAction != null) ...[
                const SizedBox(height: AppSpacing.xs),
                secondaryAction!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 图标光晕底衬：品牌主题下替代纯线性图标的单调观感
class _IconHalo extends StatelessWidget {
  const _IconHalo({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 104,
      height: 104,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  color.withValues(alpha: 0.18),
                  color.withValues(alpha: 0.02),
                ],
              ),
            ),
          ),
          Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.12),
              border: Border.all(color: color.withValues(alpha: 0.32)),
            ),
            child: Icon(icon, size: 32, color: color),
          ),
        ],
      ),
    );
  }
}
