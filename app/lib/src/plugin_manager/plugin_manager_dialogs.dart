import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';

import '../providers/app_providers.dart';
import 'ptx_import.dart';

/// 批量导入结果汇总弹窗
class ImportSummaryDialog extends StatelessWidget {
  final PtxImportOutcome outcome;

  const ImportSummaryDialog({super.key, required this.outcome});

  @override
  Widget build(BuildContext context) {
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
    return AlertDialog(
      title: const Text('导入结果'),
      content: SingleChildScrollView(
        child: Text(buffer.toString().trimRight()),
      ),
      actions: [
        TextButton(
          onPressed: Navigator.of(context).pop,
          child: const Text('确定'),
        ),
      ],
    );
  }
}

/// 安装失败的统一错误弹窗
class InstallErrorDialog extends StatelessWidget {
  final String message;

  const InstallErrorDialog({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('安装失败'),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('确定'),
        ),
      ],
    );
  }
}

/// 敏感权限授权确认弹窗（返回 true 表示用户同意安装）
class SensitivePermissionConfirmDialog extends StatelessWidget {
  final String pluginName;
  final String pluginVersion;
  final List<PluginPermission> sensitivePermissions;

  const SensitivePermissionConfirmDialog({
    super.key,
    required this.pluginName,
    required this.pluginVersion,
    required this.sensitivePermissions,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Row(
        children: [
          Icon(
            Icons.security_update_warning_outlined,
            color: theme.colorScheme.error,
            size: 24,
          ),
          const SizedBox(width: 8),
          const Text('敏感权限授权确认'),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('插件「$pluginName v$pluginVersion」申请了以下敏感权限：'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: theme.colorScheme.error.withValues(alpha: 0.4),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final p in sensitivePermissions)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        '• ${p.label}: ${p.description}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '授予后该插件可访问对应硬件或网络资源，请确认是否信任该来源。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('拒绝并取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('同意并安装'),
        ),
      ],
    );
  }
}

/// 卸载插件二次确认弹窗（返回 true 表示确认卸载）
class UninstallConfirmDialog extends StatelessWidget {
  final String pluginName;

  const UninstallConfirmDialog({super.key, required this.pluginName});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('卸载插件'),
      content: Text('确定要卸载插件「$pluginName」吗？\n卸载后相关数据将被清除。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('卸载'),
        ),
      ],
    );
  }
}

/// 插件详情与权限管理弹窗
///
/// 权限开关的读写直接作用于插件上下文与注册表，
/// 弹窗内部自持局部刷新状态，无需外层页面参与。
class PluginDetailsDialog extends ConsumerStatefulWidget {
  final ToolPlugin plugin;

  const PluginDetailsDialog({super.key, required this.plugin});

  @override
  ConsumerState<PluginDetailsDialog> createState() =>
      _PluginDetailsDialogState();
}

class _PluginDetailsDialogState extends ConsumerState<PluginDetailsDialog> {
  @override
  Widget build(BuildContext context) {
    final plugin = widget.plugin;
    final dynamicPlugin = plugin is DynamicPlugin ? plugin : null;
    final declaredPermissions =
        dynamicPlugin?.manifest.permissions ?? <PluginPermission>[];
    final grantedPermissions =
        dynamicPlugin?.context?.grantedPermissions ?? <PluginPermission>{};

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
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
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
                            color: Theme.of(context).colorScheme.errorContainer,
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
                  onChanged: (enabled) async {
                    final current = Set<PluginPermission>.from(
                      dynamicPlugin?.context?.grantedPermissions ??
                          declaredPermissions,
                    );
                    if (enabled) {
                      current.add(perm);
                    } else {
                      current.remove(perm);
                    }
                    setState(() {
                      dynamicPlugin?.context?.setGrantedPermissions(current);
                    });
                    await ref
                        .read(pluginRegistryProvider.notifier)
                        .setCustomPermissions(plugin.id, current);
                  },
                );
              }),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('完成'),
        ),
      ],
    );
  }
}
