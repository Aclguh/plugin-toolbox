import 'package:flutter/material.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';

import '../extensions/tool_plugin_ui_extension.dart';
import '../theme/app_tokens.dart';

/// 首页网格中的插件卡片。
///
/// 交互态：悬停时描边转为品牌靛青并轻微抬升，按下时整卡微缩，
/// 键盘聚焦由 InkWell 的 focusColor 承接，保证触摸 / 鼠标 / 键盘三端一致。
class PluginCard extends StatefulWidget {
  final ToolPlugin plugin;
  final VoidCallback onTap;

  const PluginCard({
    super.key,
    required this.plugin,
    required this.onTap,
  });

  @override
  State<PluginCard> createState() => _PluginCardState();
}

class _PluginCardState extends State<PluginCard> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // 多态图标：通过基类 iconProvider 获取图片源，避免对具体插件类型硬检查
    final imageProvider = widget.plugin.iconProvider;
    final Widget iconWidget = imageProvider != null
        ? ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: Image(
              // 限制解码宽度, 防止超大图标占用过多内存
              image: ResizeImage(imageProvider, width: 128),
              width: 34,
              height: 34,
              fit: BoxFit.cover,
              // 图标文件损坏或缺失时回退到矢量图标，不红屏
              errorBuilder: (_, __, ___) => Icon(
                widget.plugin.icon,
                size: 28,
                color: colorScheme.primary,
              ),
            ),
          )
        : Icon(widget.plugin.icon, size: 28, color: colorScheme.primary);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() {
        _hovered = false;
        _pressed = false;
      }),
      child: Card(
        clipBehavior: Clip.antiAlias,
        margin: EdgeInsets.zero,
        elevation: _hovered ? AppElevation.hover : AppElevation.flat,
        shadowColor: colorScheme.primary.withValues(alpha: 0.25),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          side: BorderSide(
            color: _hovered
                ? colorScheme.primary.withValues(alpha: 0.55)
                : colorScheme.outlineVariant.withValues(alpha: 0.6),
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          onTap: widget.onTap,
          splashColor: colorScheme.primary.withValues(alpha: 0.12),
          hoverColor: colorScheme.primary.withValues(alpha: 0.06),
          focusColor: colorScheme.primary.withValues(alpha: 0.14),
          onHighlightChanged: (value) => setState(() => _pressed = value),
          child: AnimatedScale(
            scale: _pressed ? 0.965 : 1,
            duration: AppMotion.instant,
            curve: AppMotion.emphasized,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm - 2,
                vertical: AppSpacing.sm + 2,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _IconTile(
                    hovered: _hovered,
                    child: iconWidget,
                  ),
                  const SizedBox(height: AppSpacing.sm - 2),
                  // 名称允许两行：中文插件名较长，单行省略会让用户无法分辨同类工具
                  Text(
                    widget.plugin.name,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: colorScheme.onSurface,
                      height: 1.25,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Flexible(
                    child: Text(
                      widget.plugin.description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 11,
                        height: 1.3,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 图标底衬：品牌靛青到薄荷青的低饱和渐变，兼顾深色底上的辨识度
class _IconTile extends StatelessWidget {
  const _IconTile({required this.child, required this.hovered});

  final Widget child;
  final bool hovered;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: AppMotion.fast,
      curve: AppMotion.emphasized,
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.md + 2),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primary.withValues(alpha: hovered ? 0.26 : 0.18),
            scheme.secondary.withValues(alpha: hovered ? 0.16 : 0.08),
          ],
        ),
        border: Border.all(
          color: scheme.primary.withValues(alpha: hovered ? 0.45 : 0.22),
        ),
      ),
      child: Center(child: child),
    );
  }
}
