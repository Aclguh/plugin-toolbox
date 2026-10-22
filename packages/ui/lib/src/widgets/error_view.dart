import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// 统一错误态：错误光晕图标 + 标题 + 可读原因 + 重试动作。
///
/// 错误色一律取自 `colorScheme.error`，随亮暗主题与动态取色自动适配，
/// 不再出现硬编码红色在品牌深蓝底上刺眼、对比度不达标的问题。
class ErrorView extends StatelessWidget {
  const ErrorView({
    super.key,
    required this.message,
    this.onRetry,
    this.title = '出错了',
    this.icon = Icons.error_outline,
    this.retryLabel = '重试',
  });

  final String message;
  final VoidCallback? onRetry;
  final String title;
  final IconData icon;
  final String retryLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final errorColor = theme.colorScheme.error;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: errorColor.withValues(alpha: 0.12),
                  border: Border.all(
                    color: errorColor.withValues(alpha: 0.3),
                  ),
                ),
                child: Icon(icon, size: 30, color: errorColor),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
              if (onRetry != null) ...[
                const SizedBox(height: AppSpacing.xl),
                FilledButton.tonalIcon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: Text(retryLabel),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
