import 'dart:io';
import 'dart:ui' show lerpDouble;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';
import 'package:plugin_toolbox_ui/plugin_toolbox_ui.dart';
import '../providers/app_providers.dart';

/// .ptx 不是 Android MIME 表中的注册类型，FileType.custom 会被 SAF 过滤器
/// 置灰不可选，因此放开为任意文件；选中后在此统一校验扩展名（批量导入逐文件过滤）。
bool isPtxPackage(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot == -1) return false;
  final ext = fileName.substring(dot + 1).toLowerCase();
  return ext == 'ptx' || ext == 'zip';
}

/// 批量导入结果: installed 为成功注册所需的插件对象, 其余为界面展示文案
@visibleForTesting
class PtxImportOutcome {
  PtxImportOutcome({
    required this.installed,
    required this.succeeded,
    required this.failed,
  });

  final List<DynamicPlugin> installed;
  final List<String> succeeded;
  final List<String> failed;
}

/// 逐文件执行安装并汇总成败; 单个文件失败不影响其余文件。
/// [installer] 注入以便测试替身 (生产环境为 PluginInstaller.installFromPtx)。
@visibleForTesting
Future<PtxImportOutcome> importPtxFiles({
  required List<PlatformFile> files,
  required Future<DynamicPlugin> Function(File file) installer,
}) async {
  final installed = <DynamicPlugin>[];
  final succeeded = <String>[];
  final failed = <String>[];
  for (final picked in files) {
    final path = picked.path;
    if (path == null) {
      failed.add('${picked.name}: 无法读取文件');
      continue;
    }
    if (!isPtxPackage(picked.name)) {
      failed.add('${picked.name}: 仅支持 .ptx 或 .zip 插件安装包');
      continue;
    }
    try {
      final plugin = await installer(File(path));
      installed.add(plugin);
      succeeded.add('${plugin.name} v${plugin.version}');
    } on FormatException catch (e) {
      failed.add('${picked.name}: ${e.message}');
    } on FileSystemException {
      failed.add('${picked.name}: 安装包文件读取失败，请确认文件完整后重试');
    } catch (_) {
      failed.add('${picked.name}: 安装失败，发生未知错误');
    }
  }
  return PtxImportOutcome(installed: installed, succeeded: succeeded, failed: failed);
}

class PluginManagerPage extends ConsumerWidget {
  const PluginManagerPage({super.key});

  Future<void> _pickAndInstall(BuildContext context, WidgetRef ref) async {
    try {
      // 批量导入: 允许一次选择多个 .ptx/.zip, 逐个安装, 单个失败不影响其余
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: true,
      );
      if (result == null || result.files.isEmpty) return;

      final outcome = await importPtxFiles(
        files: result.files,
        installer: PluginInstaller.installFromPtx,
      );

      // 注册并初始化全部成功项 (同 ID 覆盖即插件更新)
      final registry = ref.read(pluginRegistryProvider);
      for (final plugin in outcome.installed) {
        registry.register(plugin);
      }
      await registry.initializeAll();

      // 触发 UI 刷新
      ref.read(pluginRegistryProvider.notifier).refresh();
      await ref.read(pluginRegistryProvider.notifier).saveOrder();

      if (!context.mounted) return;
      if (outcome.failed.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('成功导入 ${outcome.succeeded.length} 个插件'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        _showImportSummary(context, outcome);
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

  void _showImportSummary(BuildContext context, PtxImportOutcome outcome) {
    final buffer = StringBuffer();
    if (outcome.succeeded.isNotEmpty) {
      buffer.writeln('成功 ${outcome.succeeded.length} 个:');
      for (final name in outcome.succeeded) {
        buffer.writeln('· $name');
      }
    }
    if (outcome.failed.isNotEmpty) {
      if (buffer.isNotEmpty) buffer.writeln();
      buffer.writeln('失败 ${outcome.failed.length} 个:');
      for (final reason in outcome.failed) {
        buffer.writeln('· $reason');
      }
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导入结果'),
        content: SingleChildScrollView(
          child: Text(buffer.toString().trimRight()),
        ),
        actions: [
          TextButton(onPressed: Navigator.of(ctx).pop, child: const Text('确定')),
        ],
      ),
    );
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

  void _showPluginDetails(
    BuildContext context,
    WidgetRef ref,
    ToolPlugin plugin,
  ) {
    final dynamicPlugin = plugin is DynamicPlugin ? plugin : null;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final declaredPermissions = dynamicPlugin?.manifest.permissions ?? <PluginPermission>[];
          final grantedPermissions = dynamicPlugin?.context?.grantedPermissions ?? <PluginPermission>{};

          return AlertDialog(
            title: Text(plugin.name),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('ID: ${plugin.id}'),
                  const SizedBox(height: 4),
                  Text('版本: ${plugin.version}'),
                  const SizedBox(height: 4),
                  Text('分类: ${plugin.category.label}'),
                  if (dynamicPlugin != null) ...[
                    const SizedBox(height: 4),
                    Text('作者: ${dynamicPlugin.manifest.author}'),
                    const SizedBox(height: 4),
                    Text('沙箱配额: ${dynamicPlugin.manifest.storageQuotaMb} MB'),
                  ],
                  const SizedBox(height: 12),
                  const Divider(),
                  const SizedBox(height: 6),
                  Text(
                    '权限管理',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  if (declaredPermissions.isEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      '该插件未声明任何系统权限',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                    ),
                  ] else ...[
                    const SizedBox(height: 6),
                    ...declaredPermissions.map((perm) {
                      final isGranted = grantedPermissions.contains(perm);
                      return SwitchListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Row(
                          children: [
                            Text(perm.label),
                            if (perm.isSensitive) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .errorContainer,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '敏感',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onErrorContainer,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        subtitle: Text(perm.description),
                        value: isGranted,
                        onChanged: (enabled) {
                          setDialogState(() {
                            if (enabled) {
                              dynamicPlugin?.context?.grantedPermissions.add(perm);
                            } else {
                              dynamicPlugin?.context?.grantedPermissions.remove(perm);
                            }
                          });
                        },
                      );
                    }),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('完成'),
              ),
            ],
          );
        },
      ),
    );
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
                    // 简介与版本分行渲染: 版本号独立成行且不受 maxLines 约束,
                    // 避免长简介折行占满额度后把版本号挤出可视范围
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          plugin.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '版本: ${plugin.version}',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                    trailing: Switch(
                      value: isEnabled,
                      onChanged: (val) async {
                        await registry.setEnabled(plugin.id, val);
                        ref.read(pluginRegistryProvider.notifier).refresh();
                      },
                    ),
                    onTap: () => _showPluginDetails(context, ref, plugin),
                    onLongPress: () => _confirmDelete(context, ref, plugin),
                  ),
                );
              },
            ),
    );
  }
}
