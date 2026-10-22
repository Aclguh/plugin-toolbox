import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// 全站统一的二级页面骨架。
///
/// 统一承担：标题（可带副标题）、右侧动作、底部细分割线、内容安全区，
/// 以及在平板 / 折叠屏上的正文限宽，避免同一应用里出现多种导航栏高度。
class PluginPageScaffold extends StatelessWidget {
  const PluginPageScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.floatingActionButton,
    this.subtitle,
    this.bottom,
    this.maxContentWidth,
  });

  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? floatingActionButton;

  /// 标题下方的辅助说明（例如当前筛选条件、数据来源）
  final String? subtitle;

  /// 导航栏下方的附加区域（如 TabBar）
  final PreferredSizeWidget? bottom;

  /// 正文最大宽度；为空表示铺满（插件渲染页保持铺满以避免挤压插件布局）
  final double? maxContentWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasSubtitle = subtitle != null;

    final titleWidget = hasSubtitle
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w400,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          )
        : Text(title);

    Widget content = body;
    final limit = maxContentWidth;
    if (limit != null) {
      content = Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: limit),
          child: body,
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: titleWidget,
        toolbarHeight: hasSubtitle
            ? AppLayout.appBarHeight + AppSpacing.md
            : AppLayout.appBarHeight,
        actions: actions == null
            ? null
            : [...actions!, const SizedBox(width: AppSpacing.xs)],
        bottom: bottom ??
            PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Divider(
                height: 1,
                thickness: 1,
                color: scheme.outlineVariant.withValues(alpha: 0.35),
              ),
            ),
      ),
      body: SafeArea(child: content),
      floatingActionButton: floatingActionButton,
    );
  }
}
