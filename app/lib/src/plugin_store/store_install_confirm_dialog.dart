import 'package:flutter/material.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';
import 'package:plugin_toolbox_ui/plugin_toolbox_ui.dart';
import '../../l10n/app_localizations.dart';
import 'plugin_store_page.dart';
import 'store_service.dart';

/// 插件安装与更新二次确认对话框
class StoreInstallConfirmDialog extends StatelessWidget {
  final PluginStoreItem item;

  const StoreInstallConfirmDialog({
    super.key,
    required this.item,
  });

  /// 弹出安装或更新确认对话框
  static Future<bool?> show(BuildContext context, PluginStoreItem item) {
    return showDialog<bool>(
      context: context,
      builder: (_) => StoreInstallConfirmDialog(item: item),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final isUpdate = item.state == PluginStoreInstallState.updateAvailable;
    final sensitivePermissions = item.entry.permissions
        .map(PluginPermission.fromString)
        .where((p) => p != null && p.isSensitive)
        .cast<PluginPermission>()
        .toList();

    return AppDialog(
      icon: isUpdate
          ? Icons.system_update_alt_rounded
          : Icons.download_for_offline_outlined,
      title: isUpdate
          ? (l10n?.updatePluginTitle ?? '更新插件')
          : (l10n?.installPluginTitle ?? '安装插件'),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${item.name} v${item.version}',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            item.description,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          // 弹窗内的元信息卡需显式铺满对话框宽度，Card 会自适应内容
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
                    _dialogMetaLine(
                      context,
                      '分类: ${pluginCategoryLabel(item.entry.category)}',
                    ),
                    _dialogMetaLine(context, '作者: ${item.entry.author}'),
                    _dialogMetaLine(
                      context,
                      '体积: ${item.entry.packageSizeLabel}',
                    ),
                    _dialogMetaLine(
                      context,
                      '权限: ${item.entry.permissions.isEmpty ? '无' : item.entry.permissions.map(pluginPermissionLabel).join('、')}',
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (sensitivePermissions.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            AppBanner(
              tone: AppBannerTone.danger,
              title: l10n?.sensitivePermissionsWarningTitle ?? '敏感权限授权提醒',
              message: sensitivePermissions
                  .map((p) => '• ${p.label}: ${p.description}')
                  .join('\n'),
            ),
          ],
          if (item.installedVersion != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              isUpdate
                  ? '将把本地 ${item.installedVersion} 覆盖为 ${item.version}'
                  : l10n?.localInstalledVersion(item.installedVersion!) ??
                      '本地已安装 ${item.installedVersion}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n?.cancel ?? '取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(
            isUpdate ? (l10n?.update ?? '更新') : (l10n?.install ?? '安装'),
          ),
        ),
      ],
    );
  }

  /// 弹窗内的键值信息行：冒号后数值加粗，提升扫读效率
  Widget _dialogMetaLine(BuildContext context, String text) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
