import 'dart:io';
import 'dart:ui' show lerpDouble;
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
      // .ptx 不是 Android MIME 表中的注册类型，FileType.custom 会被 SAF 过滤器
      // 置灰不可选，因此放开为任意文件，选中后再校验扩展名
      final result = await FilePicker.platform.pickFiles(type: FileType.any);

      if (result != null && result.files.single.path != null) {
        final filePath = result.files.single.path!;
        final fileName = filePath.split(Platform.pathSeparator).last;
        final dotIndex = fileName.lastIndexOf('.');
        final extension = dotIndex == -1 ? '' : fileName.substring(dotIndex + 1).toLowerCase();
        if (extension != 'ptx' && extension != 'zip') {
          if (!context.mounted) return;
          _showInstallError(context, '仅支持导入 .ptx 或 .zip 插件安装包');
          return;
        }
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
    } on FormatException catch (e) {
      if (!context.mounted) return;
      _showInstallError(context, '安装包无效：${e.message}');
    } on FileSystemException {
      if (!context.mounted) return;
      _showInstallError(context, '安装包文件读取失败，请确认文件完整后重试');
    } catch (_) {
      // 未预期的异常不向用户展示原始堆栈信息
      if (!context.mounted) return;
      _showInstallError(context, '安装失败，发生未知错误，请重试');
    }
  }

  void _showInstallError(BuildContext context, String message) {
    if (context.mounted) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('安装失败'),
          content: Text(message),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('确定')),
          ],
        ),
      );
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
    // 多态图标：经基类 iconProvider 获取图片源，避免对动态插件类型硬检查；
    // 图片解码失败或文件缺失时回退矢量图标，不在 build 中做同步磁盘检查
    final imageProvider = plugin.iconProvider;
    if (imageProvider != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image(
          image: ResizeImage(imageProvider, width: 128),
          width: 32,
          height: 32,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Icon(
            plugin.icon,
            size: 30,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      );
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
              proxyDecorator: (Widget child, int index, Animation<double> animation) {
                return AnimatedBuilder(
                  animation: animation,
                  builder: (BuildContext context, Widget? child) {
                    final double animValue = Curves.easeInOut.transform(animation.value);
                    final double elevation = lerpDouble(2, 8, animValue) ?? 6;
                    return Material(
                      color: Colors.transparent,
                      elevation: 0,
                      child: Theme(
                        data: Theme.of(context).copyWith(
                          cardTheme: Theme.of(context).cardTheme.copyWith(
                            elevation: elevation,
                            shadowColor: Colors.black.withValues(alpha: 0.6),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(
                                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
                                width: 1.5,
                              ),
                            ),
                          ),
                        ),
                        child: child!,
                      ),
                    );
                  },
                  child: child,
                );
              },
              itemBuilder: (context, index) {
                final plugin = allPlugins[index];
                final isEnabled = registry.isEnabled(plugin.id);
                return Card(
                  key: ValueKey(plugin.id),
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  clipBehavior: Clip.antiAlias,
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
