import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import 'section_header.dart';

/// 统一分组容器：标题 + 卡片内的若干行，行间使用同一条细分隔线。
///
/// 设置页、插件详情等"条目集合"页面统一使用此结构，
/// 避免出现有的分组带卡片、有的分组裸露在背景上的割裂观感。
class AppSection extends StatelessWidget {
  const AppSection({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
    this.icon,
    this.trailing,
    this.padding = const EdgeInsets.only(bottom: AppSpacing.md),
    this.separated = true,
  });

  final String title;
  final List<Widget> children;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;
  final bool separated;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0 && separated) {
        rows.add(
          Divider(
            height: 1,
            thickness: 1,
            indent: AppSpacing.lg,
            endIndent: AppSpacing.lg,
            color: scheme.outlineVariant.withValues(alpha: 0.35),
          ),
        );
      }
      rows.add(children[i]);
    }

    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: title,
            subtitle: subtitle,
            icon: icon,
            trailing: trailing,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: rows,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
