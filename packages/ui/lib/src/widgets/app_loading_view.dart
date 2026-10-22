import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// 统一加载态：品牌进度环 + 说明文案。
///
/// 只有一处无限动画（进度环），且仅在真正加载期间挂载，
/// 不会给测试或后台页面留下持续重绘的负担。
class AppLoadingView extends StatelessWidget {
  const AppLoadingView({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 44,
            height: 44,
            child: CircularProgressIndicator(
              strokeWidth: 2.6,
              color: scheme.primary,
              backgroundColor: scheme.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
          if (label != null) ...[
            const SizedBox(height: AppSpacing.lg),
            Text(
              label!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 骨架占位块：仅做一次淡入，避免无限动画在测试环境中阻塞 `pumpAndSettle`
class AppSkeleton extends StatelessWidget {
  const AppSkeleton({
    super.key,
    required this.width,
    required this.height,
    this.radius = AppRadius.sm,
  });

  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 450),
      curve: AppMotion.decelerate,
      builder: (context, value, child) => Opacity(
        opacity: 0.35 + 0.45 * value,
        child: child,
      ),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          color: scheme.surfaceContainerHigh.withValues(alpha: 0.7),
        ),
      ),
    );
  }
}

/// 列表骨架：用于目录 / 商店等首屏拉取场景，先给出结构再填充内容
class AppSkeletonList extends StatelessWidget {
  const AppSkeletonList({super.key, this.itemCount = 4});

  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.xxl,
      ),
      itemCount: itemCount,
      itemBuilder: (context, index) => const _SkeletonCard(),
    );
  }
}

/// 单条骨架卡片：与真实插件卡片的行高、圆角保持一致，
/// 数据到达后内容"原地替换"而非整页跳动
class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(bottom: AppSpacing.md),
      child: Card(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  AppSkeleton(width: 56, height: 18),
                  Spacer(),
                  AppSkeleton(width: 68, height: 32, radius: 12),
                ],
              ),
              SizedBox(height: AppSpacing.md),
              AppSkeleton(width: double.infinity, height: 12),
              SizedBox(height: AppSpacing.sm),
              FractionallySizedBox(
                widthFactor: 0.6,
                child: AppSkeleton(width: double.infinity, height: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
