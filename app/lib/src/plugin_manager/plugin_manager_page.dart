import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';
import 'package:plugin_toolbox_ui/plugin_toolbox_ui.dart';
import '../providers/app_providers.dart';

class PluginManagerPage extends ConsumerWidget {
  const PluginManagerPage({super.key});

  Future<void> _pickAndInstall(BuildContext context, WidgetRef ref) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['ptx', 'zip'],
      );

      if (result != null && result.files.single.path != null) {
        final filePath = result.files.single.path!;
        final file = File(filePath);

        // 安装解析
        final plugin = await PluginInstaller.installFromPtx(file);

        // 注册到系统
        final registry = ref.read(pluginRegistryProvider);
        registry.register(plugin);
        await registry.initializeAll();

        // 触发 UI 刷新
        ref.read(pluginRegistryProvider.notifier).refresh();
        await ref.read(pluginRegistryProvider.notifier).saveOrder();

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('插件 [${plugin.name}] 安装成功！'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('安装失败'),
            content: Text(e.toString()),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('确定')),
            ],
          ),
        );
      }
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    ToolPlugin plugin,
  ) async {
    if (!plugin.isDynamic) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('内置插件无法删除'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('卸载插件'),
        content: Text('确定要卸载插件「${plugin.name}」吗？\n卸载后相关数据将被清除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('卸载'),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      final registry = ref.read(pluginRegistryProvider);
      await registry.unregister(plugin.id);
      await ref.read(pluginRegistryProvider.notifier).saveOrder();
      ref.read(pluginRegistryProvider.notifier).refresh();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('插件「${plugin.name}」已卸载'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Widget _buildPluginIcon(BuildContext context, ToolPlugin plugin) {
    if (plugin is DynamicPlugin) {
      final iconFile = plugin.iconFile;
      if (iconFile != null && iconFile.existsSync()) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Image.file(
            iconFile,
            width: 32,
            height: 32,
            fit: BoxFit.cover,
          ),
        );
      }
    }
    return Icon(
      plugin.icon,
      size: 30,
      color: Theme.of(context).colorScheme.primary,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final registry = ref.watch(pluginRegistryProvider);
    final allPlugins = registry.allPlugins;

    return PluginPageScaffold(
      title: '插件管理中心',
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('导入 .ptx 插件'),
        onPressed: () => _pickAndInstall(context, ref),
      ),
      body: allPlugins.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('暂无插件，点击右下角按钮导入'),
              ),
            )
          : ReorderableListView.builder(
              buildDefaultDragHandles: false,
              padding: const EdgeInsets.only(bottom: 80),
              header: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Text(
                  '长按卡片可删除插件，长按左侧图标可拖动排序',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                ),
              ),
              itemCount: allPlugins.length,
              onReorderItem: (oldIndex, newIndex) async {
                await ref.read(pluginRegistryProvider.notifier).reorder(oldIndex, newIndex);
              },
              itemBuilder: (context, index) {
                final plugin = allPlugins[index];
                final isEnabled = registry.isEnabled(plugin.id);
                return Card(
                  key: ValueKey(plugin.id),
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                    leading: ReorderableDelayedDragStartListener(
                      index: index,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.grab,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.drag_indicator,
                                color: Theme.of(context).colorScheme.outline,
                                size: 22,
                              ),
                              const SizedBox(width: 8),
                              _buildPluginIcon(context, plugin),
                            ],
                          ),
                        ),
                      ),
                    ),
                    title: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            plugin.name,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (plugin.isDynamic) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '动态',
                              style: TextStyle(
                                fontSize: 10,
                                color: Theme.of(context).colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    subtitle: Text(
                      '${plugin.description}\n版本: ${plugin.version}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Switch(
                      value: isEnabled,
                      onChanged: (val) async {
                        await registry.setEnabled(plugin.id, val);
                        ref.read(pluginRegistryProvider.notifier).refresh();
                      },
                    ),
                    onLongPress: () => _confirmDelete(context, ref, plugin),
                  ),
                );
              },
            ),
    );
  }
}
