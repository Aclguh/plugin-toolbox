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
      body: ListView(
        padding: const EdgeInsets.only(bottom: 80),
        children: [
          const SectionHeader(title: '已安装插件'),
          if (allPlugins.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('暂无插件，点击右下角按钮导入'),
              ),
            ),
          ...allPlugins.map((plugin) {
            final isEnabled = registry.isEnabled(plugin.id);
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                leading: Icon(plugin.icon),
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
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Switch(
                      value: isEnabled,
                      onChanged: (val) async {
                        await registry.setEnabled(plugin.id, val);
                        ref.read(pluginRegistryProvider.notifier).refresh();
                      },
                    ),
                    if (plugin.isDynamic)
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 22),
                        tooltip: '卸载',
                        visualDensity: VisualDensity.compact,
                        onPressed: () async {
                          await registry.unregister(plugin.id);
                          ref.read(pluginRegistryProvider.notifier).refresh();
                        },
                      ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
