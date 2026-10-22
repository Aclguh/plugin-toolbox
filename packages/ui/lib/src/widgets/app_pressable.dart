import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// 统一的可交互容器：一次性提供 hover / focus / press 三态反馈。
///
/// Flutter 原生 `InkWell` 只覆盖水波纹，桌面与平板上的悬停提示、
/// 键盘聚焦描边需要额外手写；此处集中封装，保证所有可点区域
/// （卡片、列表项、图标按钮）具有完全一致的反馈节奏。
class AppPressable extends StatefulWidget {
  const AppPressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.onHighlightChanged,
    this.borderRadius,
    this.pressedScale = 0.985,
    this.hoverColor,
    this.padding = EdgeInsets.zero,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final ValueChanged<bool>? onHighlightChanged;
  final BorderRadius? borderRadius;
  final double pressedScale;
  final Color? hoverColor;
  final EdgeInsetsGeometry padding;
  final String? semanticLabel;

  @override
  State<AppPressable> createState() => _AppPressableState();
}

class _AppPressableState extends State<AppPressable> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  bool get _enabled => widget.onTap != null || widget.onLongPress != null;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
    widget.onHighlightChanged?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = widget.borderRadius ?? BorderRadius.circular(AppRadius.xl);
    final hoverOverlay =
        widget.hoverColor ?? scheme.primary.withValues(alpha: 0.06);

    return Semantics(
      button: _enabled,
      label: widget.semanticLabel,
      child: MouseRegion(
        cursor: _enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() {
          _hovered = false;
          _setPressed(false);
        }),
        child: FocusableActionDetector(
          enabled: _enabled,
          onShowFocusHighlight: (value) => setState(() => _focused = value),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: _enabled ? (_) => _setPressed(true) : null,
            onTapUp: _enabled ? (_) => _setPressed(false) : null,
            onTapCancel: _enabled ? () => _setPressed(false) : null,
            onTap: widget.onTap,
            onLongPress: widget.onLongPress,
            child: AnimatedScale(
              scale: _pressed ? widget.pressedScale : 1,
              duration: AppMotion.instant,
              curve: AppMotion.emphasized,
              child: AnimatedContainer(
                duration: AppMotion.fast,
                curve: AppMotion.emphasized,
                padding: widget.padding,
                decoration: BoxDecoration(
                  borderRadius: radius,
                  color: _hovered ? hoverOverlay : Colors.transparent,
                  border: Border.all(
                    color: _focused
                        ? scheme.primary.withValues(alpha: 0.7)
                        : Colors.transparent,
                    width: 1.2,
                  ),
                ),
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
