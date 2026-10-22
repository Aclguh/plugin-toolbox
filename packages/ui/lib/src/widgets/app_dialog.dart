import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// 弹窗内的圆形图标底衬
class AppDialogIcon extends StatelessWidget {
  const AppDialogIcon({super.key, required this.icon, this.color});

  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final accent = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: accent.withValues(alpha: 0.12),
        border: Border.all(color: accent.withValues(alpha: 0.32)),
      ),
      child: Icon(icon, size: 26, color: accent),
    );
  }
}

/// 统一弹窗外壳。
///
/// 统一承担：图标 + 标题 + 副标题的层级排版、长内容滚动、
/// 动作按钮换行对齐；业务弹窗只需提供内容与动作，视觉细节不再重复实现。
class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    this.title,
    this.subtitle,
    this.icon,
    this.iconColor,
    this.content,
    this.actions = const <Widget>[],
    this.scrollable = true,
  });

  final String? title;
  final String? subtitle;
  final IconData? icon;
  final Color? iconColor;
  final Widget? content;
  final List<Widget> actions;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Widget? header;
    if (title != null || subtitle != null) {
      header = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null)
            Text(
              title!,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
          if (subtitle != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              subtitle!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      );
    }

    Widget? body;
    if (content != null) {
      body = scrollable ? SingleChildScrollView(child: content) : content;
    }

    return AlertDialog(
      icon: icon != null ? AppDialogIcon(icon: icon!, color: iconColor) : null,
      title: header,
      titlePadding: EdgeInsets.fromLTRB(
        AppSpacing.xxl,
        // 有图标时图标自身已带下留白，标题顶部收紧避免出现大块空档
        icon == null ? AppSpacing.xl : AppSpacing.xs,
        AppSpacing.xxl,
        AppSpacing.md,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
      actionsPadding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
      ),
      content: body,
      actions: actions,
      actionsAlignment: MainAxisAlignment.end,
      actionsOverflowAlignment: OverflowBarAlignment.end,
      actionsOverflowButtonSpacing: AppSpacing.sm,
    );
  }
}
