import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';
import 'package:plugin_toolbox_ui/plugin_toolbox_ui.dart';

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

    final hasFailure = outcome.failed.isNotEmpty;
    final theme = Theme.of(context);

    return AppDialog(
      icon: hasFailure
          ? Icons.report_gmailerrorred_outlined
          : Icons.task_alt_rounded,
      iconColor:
          hasFailure ? theme.colorScheme.error : context.appColors.success,
      title: '导入结果',
      content: Container(
        width: double.maxFinite,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Text(
          buffer.toString().trimRight(),
          style: theme.textTheme.bodySmall?.copyWith(
            fontFamily: AppTypography.monospace,
            height: 1.55,
            color: theme.colorScheme.onSurface,
          ),
        ),
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
    return AppDialog(
      icon: Icons.error_outline_rounded,
      iconColor: Theme.of(context).colorScheme.error,
      title: '安装失败',
      content: Text(
        message,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
      actions: [
        FilledButton.tonal(
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
    return AppDialog(
      icon: Icons.security_update_warning_outlined,
      iconColor: theme.colorScheme.error,
      title: '敏感权限授权确认',
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('插件「$pluginName v$pluginVersion」申请了以下敏感权限：'),
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: theme.colorScheme.error.withValues(alpha: 0.4),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final p in sensitivePermissions)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.xxs,
                    ),
                    child: Text(
                      '• ${p.label}: ${p.description}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            '授予后该插件可访问对应硬件或网络资源，请确认是否信任该来源。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('拒绝并取消'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          ),
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
    final theme = Theme.of(context);
    return AppDialog(
      icon: Icons.delete_outline_rounded,
      iconColor: theme.colorScheme.error,
      title: '卸载插件',
      content: Text('确定要卸载插件「$pluginName」吗？\n卸载后相关数据将被清除。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return AppDialog(
      icon: Icons.extension_outlined,
      title: plugin.name,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: double.maxFinite,
            child: Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _metaRow(context, 'ID: ${plugin.id}'),
                    _metaRow(context, '版本: ${plugin.version}'),
                    _metaRow(context, '分类: ${plugin.category.label}'),
                    if (dynamicPlugin != null) ...[
                      _metaRow(context, '作者: ${dynamicPlugin.manifest.author}'),
                      _metaRow(
                        context,
                        '沙箱配额: ${dynamicPlugin.manifest.storageQuotaMb} MB',
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            '权限管理',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
            ),
          ),
          if (declaredPermissions.isEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              '该插件未声明任何系统权限',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.outline,
              ),
            ),
          ] else ...[
            const SizedBox(height: AppSpacing.xs),
            ...declaredPermissions.map((perm) {
              final isGranted = grantedPermissions.contains(perm);
              return SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Row(
                  children: [
                    Text(perm.label),
                    if (perm.isSensitive) ...[
                      const SizedBox(width: AppSpacing.sm - 2),
                      const AppBadge(
                        label: '敏感',
                        tone: AppBadgeTone.danger,
                        dense: true,
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
          const SizedBox(height: AppSpacing.xs),
        ],
      ),
      actions: [
        if (dynamicPlugin != null)
          TextButton.icon(
            key: const Key('export_plugin_button'),
            icon: const Icon(Icons.drive_file_move_outlined, size: 18),
            label: const Text('导出 .ptx'),
            onPressed: () => _exportPlugin(context, dynamicPlugin),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('完成'),
        ),
      ],
    );
  }

  Widget _metaRow(BuildContext context, String text) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs + 1),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Future<void> _exportPlugin(
    BuildContext context,
    DynamicPlugin dynamicPlugin,
  ) async {
    try {
      final bytes = await PluginInstaller.exportToBytes(dynamicPlugin.rootDir);
      final filename = '${dynamicPlugin.id}_v${dynamicPlugin.version}.ptx';

      final outputPath = await FilePicker.platform.saveFile(
        dialogTitle: '导出插件安装包',
        fileName: filename,
        type: FileType.custom,
        allowedExtensions: ['ptx', 'zip'],
        bytes: Uint8List.fromList(bytes),
      );

      if (outputPath != null && context.mounted) {
        final file = File(outputPath);
        if (!await file.exists() || await file.length() == 0) {
          await file.writeAsBytes(bytes, flush: true);
        }
        if (context.mounted) {
          AppSnack.success(context, '插件已导出至: $outputPath');
        }
      }
    } catch (e) {
      if (context.mounted) {
        AppSnack.error(context, '导出失败: $e');
      }
    }
  }
}
