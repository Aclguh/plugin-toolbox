import 'dart:async';
import 'dart:io';
import 'dart:ui' show lerpDouble;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';
import 'package:plugin_toolbox_ui/plugin_toolbox_ui.dart';
import '../providers/app_providers.dart';
import 'plugin_manager_dialogs.dart';
import 'ptx_import.dart';

// 导入管线与结果类型从 ptx_import.dart 拆出，保持原有对外引用路径不变
export 'ptx_import.dart';

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
        installer: (file) => PluginInstaller.installFromPtx(
          file,
          signatureVerifier: PluginSignatureVerifier(
            requireSignature: ref.read(pluginSecurityModeProvider) ==
                PluginSecurityMode.strict,
          ),
        ),
      );

      final registry = ref.read(pluginRegistryProvider);
      final pluginsToRegister = <DynamicPlugin>[];
      final securityMode = ref.read(pluginSecurityModeProvider);
      for (final plugin in outcome.installed) {
        final isSigned = File('${plugin.rootDir.path}/plugin.sig').existsSync();
        if (!isSigned &&
            securityMode == PluginSecurityMode.warning &&
            context.mounted) {
          final approved = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (_) => UnsignedPluginWarningDialog(
              pluginName: plugin.name,
              pluginVersion: plugin.version,
            ),
          );
          if (approved != true) {
            await PluginInstaller.uninstall(plugin.id);
            outcome.succeeded.remove('${plugin.name} v${plugin.version}');
            outcome.failed.add('${plugin.name}: 用户取消安装未签名插件');
            continue;
          }
        }
        final sensitivePerms =
            plugin.manifest.permissions.where((p) => p.isSensitive).toList();
        if (sensitivePerms.isNotEmpty && context.mounted) {
          final approved = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (_) => SensitivePermissionConfirmDialog(
              pluginName: plugin.name,
              pluginVersion: plugin.version,
              sensitivePermissions: sensitivePerms,
            ),
          );
          if (approved != true) {
            // 用户拒绝授权，清理沙箱目录并移至失败列表
            await PluginInstaller.uninstall(plugin.id);
            outcome.succeeded.remove('${plugin.name} v${plugin.version}');
            outcome.failed.add('${plugin.name}: 用户拒绝授权敏感权限');
            continue;
          }
        }
        pluginsToRegister.add(plugin);
      }

      // 注册并初始化全部获授权项 (同 ID 覆盖即插件更新)
      for (final plugin in pluginsToRegister) {
        final existingPerms = registry.getCustomPermissions(plugin.id);
        if (existingPerms != null) {
          final merged = Set<PluginPermission>.from(existingPerms)
            ..addAll(plugin.manifest.permissions);
          registry.setCustomPermissions(plugin.id, merged);
        }
        registry.register(plugin);
        await registry.initializePlugin(plugin.id);
      }

      // 触发 UI 刷新
      ref.read(pluginRegistryProvider.notifier).refresh();
      await ref.read(pluginRegistryProvider.notifier).saveOrder();

      if (!context.mounted) return;
      if (outcome.failed.isEmpty) {
        AppSnack.success(context, '成功导入 ${outcome.succeeded.length} 个插件');
      } else {
        // 结果汇总弹窗为纯展示，无需等待其关闭
        unawaited(showDialog(
          context: context,
          builder: (_) => ImportSummaryDialog(outcome: outcome),
        ));
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
        builder: (_) => InstallErrorDialog(message: message),
      );
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    ToolPlugin plugin,
  ) async {
    if (!plugin.isDynamic) {
      AppSnack.info(context, '内置插件无法删除');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => UninstallConfirmDialog(pluginName: plugin.name),
    );

    if (confirmed == true && context.mounted) {
      final registry = ref.read(pluginRegistryProvider);
      await registry.unregister(plugin.id);
      await ref.read(pluginRegistryProvider.notifier).saveOrder();
      await ref.read(pluginRegistryProvider.notifier).saveDisabledPlugins();
      await ref
          .read(pluginRegistryProvider.notifier)
          .removeCustomPermissions(plugin.id);
      ref.read(pluginRegistryProvider.notifier).refresh();

      if (context.mounted) {
        AppSnack.success(context, '插件「${plugin.name}」已卸载');
      }
    }
  }

  Widget _buildPluginIcon(BuildContext context, ToolPlugin plugin) {
    final scheme = Theme.of(context).colorScheme;
    // 多态图标：经基类 iconProvider 获取图片源，避免对动态插件类型硬检查；
    // 图片解码失败或文件缺失时回退矢量图标，不在 build 中做同步磁盘检查
    final imageProvider = plugin.iconProvider;
    final Widget child;
    if (imageProvider != null) {
      child = ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.xs),
        child: Image(
          image: ResizeImage(imageProvider, width: 128),
          width: 32,
          height: 32,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Icon(
            plugin.icon,
            size: 26,
            color: scheme.primary,
          ),
        ),
      );
    } else {
      child = Icon(plugin.icon, size: 26, color: scheme.primary);
    }

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.md),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            scheme.primary.withValues(alpha: 0.18),
            scheme.secondary.withValues(alpha: 0.08),
          ],
        ),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.2)),
      ),
      child: Center(child: child),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 仅跟随全量插件列表重建：注册表缓存在排序/启禁用变更时失效重建列表实例，
    // 无关 EventBus 事件不再触发本页刷新；开关态在每次重建时读取最新值
    final allPlugins = ref.watch(allPluginListProvider);

    return PluginPageScaffold(
      title: '插件管理中心',
      subtitle: allPlugins.isEmpty
          ? '导入 .ptx 插件包以扩展工具箱能力'
          : '${allPlugins.length} 个插件 · 长按卡片可卸载',
      maxContentWidth: AppLayout.maxContentWidth,
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('导入 .ptx 插件'),
        onPressed: () => _pickAndInstall(context, ref),
      ),
      body: allPlugins.isEmpty
          ? AppEmptyState(
              icon: Icons.inventory_2_outlined,
              title: '暂无插件，点击右下角按钮导入',
              message: '支持一次选择多个 .ptx / .zip 安装包，安装完成后将自动启用。',
              action: FilledButton.tonalIcon(
                onPressed: () => _pickAndInstall(context, ref),
                icon: const Icon(Icons.folder_open_outlined, size: 18),
                label: const Text('从本地选择文件'),
              ),
            )
          : Column(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.md,
                    AppSpacing.lg,
                    AppSpacing.xs,
                  ),
                  child: AppBanner(
                    message: '长按卡片可删除插件，长按左侧图标可拖动排序',
                    icon: Icons.touch_app_outlined,
                  ),
                ),
                Expanded(
                  child: ReorderableListView.builder(
                    buildDefaultDragHandles: false,
                    padding: const EdgeInsets.only(
                      bottom: AppLayout.listBottomInset,
                    ),
                    itemCount: allPlugins.length,
                    onReorderItem: (oldIndex, newIndex) async {
                      await ref
                          .read(pluginRegistryProvider.notifier)
                          .reorder(oldIndex, newIndex);
                    },
                    proxyDecorator:
                        (Widget child, int index, Animation<double> animation) {
                      return AnimatedBuilder(
                        animation: animation,
                        builder: (BuildContext context, Widget? child) {
                          final double animValue =
                              Curves.easeInOut.transform(animation.value);
                          final double elevation =
                              lerpDouble(2, 8, animValue) ?? 6;
                          return Material(
                            color: Colors.transparent,
                            elevation: 0,
                            child: Theme(
                              data: Theme.of(context).copyWith(
                                cardTheme: Theme.of(context).cardTheme.copyWith(
                                      elevation: elevation,
                                      shadowColor:
                                          Colors.black.withValues(alpha: 0.6),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(
                                          AppRadius.xl,
                                        ),
                                        side: BorderSide(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary
                                              .withValues(alpha: 0.8),
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
                      // 列表实例变化（含启禁用触发的缓存失效）即驱动整页重建，
                      // 此处直接读取注册表最新启禁用态即可保持一致
                      final isEnabled =
                          ref.read(pluginRegistryProvider).isEnabled(plugin.id);
                      return _PluginManagerTile(
                        key: ValueKey(plugin.id),
                        index: index,
                        plugin: plugin,
                        enabled: isEnabled,
                        icon: _buildPluginIcon(context, plugin),
                        onTap: () => showDialog(
                          context: context,
                          builder: (_) => PluginDetailsDialog(plugin: plugin),
                        ),
                        onLongPress: () => _confirmDelete(context, ref, plugin),
                        onEnabledChanged: (val) async {
                          await ref
                              .read(pluginRegistryProvider.notifier)
                              .setEnabled(plugin.id, val);
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

/// 管理中心的单条插件卡片：拖拽手柄 + 图标 + 信息 + 启停开关
class _PluginManagerTile extends StatelessWidget {
  const _PluginManagerTile({
    super.key,
    required this.index,
    required this.plugin,
    required this.enabled,
    required this.icon,
    required this.onTap,
    required this.onLongPress,
    required this.onEnabledChanged,
  });

  final int index;
  final ToolPlugin plugin;
  final bool enabled;
  final Widget icon;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final ValueChanged<bool> onEnabledChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xs + 2,
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        onTap: onTap,
        onLongPress: onLongPress,
        hoverColor: scheme.primary.withValues(alpha: 0.05),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
          ),
          child: Row(
            children: [
              ReorderableDelayedDragStartListener(
                index: index,
                child: MouseRegion(
                  cursor: SystemMouseCursors.grab,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                      vertical: AppSpacing.sm,
                    ),
                    child: Icon(
                      Icons.drag_indicator,
                      color: scheme.outline,
                      size: 22,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              icon,
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 名称独占整行：类型徽标下沉至元信息行，
                    // 长插件名不再被徽标挤压成省略号
                    Text(
                      plugin.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    // 简介与版本分行渲染: 版本号独立成行且不受 maxLines 约束,
                    // 避免长简介折行占满额度后把版本号挤出可视范围
                    Text(
                      plugin.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            '版本: ${plugin.version}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.outline,
                            ),
                          ),
                        ),
                        if (plugin.isDynamic) ...[
                          const SizedBox(width: AppSpacing.sm - 2),
                          const AppBadge(
                            label: '动态',
                            tone: AppBadgeTone.primary,
                            dense: true,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Switch(
                value: enabled,
                onChanged: onEnabledChanged,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
