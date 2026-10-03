import 'package:flutter/material.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';

class PluginCard extends StatelessWidget {
  final ToolPlugin plugin;
  final VoidCallback onTap;

  const PluginCard({
    super.key,
    required this.plugin,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // 多态图标：通过基类 iconProvider 获取图片源，避免对具体插件类型硬检查
    final imageProvider = plugin.iconProvider;
    final Widget iconWidget = imageProvider != null
        ? ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image(
              // 限制解码宽度, 防止超大图标占用过多内存
              image: ResizeImage(imageProvider, width: 128),
              width: 40,
              height: 40,
              fit: BoxFit.cover,
              // 图标文件损坏或缺失时回退到矢量图标，不红屏
              errorBuilder: (_, __, ___) =>
                  Icon(plugin.icon, size: 38, color: colorScheme.primary),
            ),
          )
        : Icon(plugin.icon, size: 38, color: colorScheme.primary);

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              iconWidget,
              const SizedBox(height: 6),
              Text(
                plugin.name,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Flexible(
                child: Text(
                  plugin.description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 11,
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
    );
  }
}
