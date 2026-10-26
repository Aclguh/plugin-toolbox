import 'package:flutter/material.dart';
import 'dui_localizations.dart';

/// 声明式 UI 节点级局部错误边界组件
///
/// 当某个组件节点在创建或构建期间发生异常时，捕获异常并降级展示局部的错误占位组件，
/// 避免单个非关键组件的解析或渲染失败导致整页崩溃。
class DuiNodeErrorBoundary extends StatelessWidget {
  final String nodeType;
  final Widget Function() builder;
  final Widget Function(Object error, StackTrace? stackTrace) fallback;

  const DuiNodeErrorBoundary({
    super.key,
    required this.nodeType,
    required this.builder,
    required this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    try {
      return builder();
    } catch (e, st) {
      return fallback(e, st);
    }
  }
}

/// 节点级错误占位展示组件
class DuiErrorPlaceholder extends StatelessWidget {
  final String type;
  final Object error;
  final StackTrace? stackTrace;

  const DuiErrorPlaceholder({
    super.key,
    required this.type,
    required this.error,
    this.stackTrace,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final errorColor = theme.colorScheme.error;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: errorColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: errorColor.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, size: 16, color: errorColor),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              DuiLocalizations.of(context).componentError(type, error),
              style: theme.textTheme.bodySmall?.copyWith(
                color: errorColor,
                height: 1.4,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
