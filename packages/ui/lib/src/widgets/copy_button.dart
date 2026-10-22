import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_tokens.dart';
import 'app_snack.dart';

/// 统一的复制按钮：低饱和品牌底 + 点击后轻量反馈。
class CopyButton extends StatelessWidget {
  final String text;
  final String tooltip;

  const CopyButton({super.key, required this.text, this.tooltip = '复制'});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return IconButton(
      icon: const Icon(Icons.content_copy, size: 18),
      tooltip: tooltip,
      style: IconButton.styleFrom(
        foregroundColor: scheme.primary,
        backgroundColor: scheme.primary.withValues(alpha: 0.1),
        minimumSize: const Size(36, 36),
        padding: const EdgeInsets.all(AppSpacing.sm),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
      ),
      onPressed: () {
        Clipboard.setData(ClipboardData(text: text));
        AppSnack.success(context, '已复制到剪贴板');
      },
    );
  }
}
