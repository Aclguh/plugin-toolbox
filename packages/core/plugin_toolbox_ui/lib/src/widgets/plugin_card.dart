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

    Widget iconWidget;
    if (plugin is DynamicPlugin) {
      final dynamicPlugin = plugin as DynamicPlugin;
      final iconFile = dynamicPlugin.iconFile;
      if (iconFile != null && iconFile.existsSync()) {
        iconWidget = ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(
            iconFile,
            width: 40,
            height: 40,
            fit: BoxFit.cover,
          ),
        );
      } else {
        iconWidget = Icon(plugin.icon, size: 38, color: colorScheme.primary);
      }
    } else {
      iconWidget = Icon(plugin.icon, size: 38, color: colorScheme.primary);
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
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
