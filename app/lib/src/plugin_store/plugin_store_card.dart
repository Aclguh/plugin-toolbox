import 'package:flutter/material.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';
import 'package:plugin_toolbox_ui/plugin_toolbox_ui.dart';
import '../../l10n/app_localizations.dart';
import 'plugin_store_page.dart';
import 'store_service.dart';

/// 插件商店单项展示与操作卡片
class PluginStoreCard extends StatelessWidget {
  final PluginStoreItem item;
  final bool isBusy;
  final VoidCallback onAction;

  const PluginStoreCard({
    super.key,
    required this.item,
    required this.isBusy,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final updateAvailable =
        item.state == PluginStoreInstallState.updateAvailable;
    final installed = item.installedVersion != null;

    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xs + 2,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
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
                    border: Border.all(
                      color: scheme.primary.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Icon(
                    pluginCategoryIcon(item.entry.category),
                    size: 20,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 名称独占一行：安装态徽标下沉到下一行，避免长插件名被挤压
                      Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        '版本 ${item.version} · ${pluginCategoryLabel(item.entry.category)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      if (installed) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Row(
                          children: [
                            if (updateAvailable) ...[
                              AppBadge(
                                label: l10n?.updateAvailableBadge ?? '可更新',
                                tone: AppBadgeTone.warning,
                                dense: true,
                              ),
                              const SizedBox(width: AppSpacing.sm - 2),
                            ],
                            Flexible(
                              child: Text(
                                l10n?.localInstalledVersion(
                                        item.installedVersion!) ??
                                    '本地已安装 ${item.installedVersion}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: scheme.outline,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                _buildAction(context, isBusy, updateAvailable),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              item.description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                _metaItem(
                  context,
                  Icons.person_outline_rounded,
                  '作者 ${item.entry.author}',
                ),
                _metaItem(
                  context,
                  Icons.inventory_2_outlined,
                  '体积 ${item.entry.packageSizeLabel}',
                ),
                _metaItem(
                  context,
                  Icons.key_outlined,
                  '权限 ${item.entry.permissions.isEmpty ? '无' : item.entry.permissions.map(pluginPermissionLabel).join('/')}',
                ),
              ],
            ),
            if (!item.minAppVersionSatisfied) ...[
              const SizedBox(height: AppSpacing.sm),
              AppBanner(
                tone: AppBannerTone.warning,
                message: '需要宿主版本 ${item.entry.minAppVersion} 及以上',
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 元信息胶囊：图标 + 文本，替代长串拼接文案
  Widget _metaItem(BuildContext context, IconData icon, String text) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxs + 1,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.xs),
          Text(
            text,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAction(
    BuildContext context,
    bool busy,
    bool updateAvailable,
  ) {
    final l10n = AppLocalizations.of(context);
    if (busy) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (!item.minAppVersionSatisfied) {
      return Text(
        l10n?.versionNotSatisfied ?? '版本不满足',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
      );
    }
    if (item.state == PluginStoreInstallState.upToDate) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.check_circle_outline_rounded,
            size: 14,
            color: context.appColors.success,
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            l10n?.upToDate ?? '已是最新',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: context.appColors.success,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      );
    }
    // 安装/更新按钮使用紧凑内边距：列表项右侧留给插件名称的宽度更充裕
    return FilledButton.tonal(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.xs,
        ),
      ),
      onPressed: onAction,
      child: Text(
          updateAvailable ? (l10n?.update ?? '更新') : (l10n?.install ?? '安装')),
    );
  }
}
