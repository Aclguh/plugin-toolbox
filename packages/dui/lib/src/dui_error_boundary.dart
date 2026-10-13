import 'package:flutter/material.dart';

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
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0x33FF5252) : const Color(0x1AFF5252),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: Colors.redAccent.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 16, color: Colors.redAccent),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              '组件 [$type] 加载异常: $error',
              style: const TextStyle(
                fontSize: 12,
                color: Colors.redAccent,
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
