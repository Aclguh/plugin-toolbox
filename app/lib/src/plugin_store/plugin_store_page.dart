import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';
import 'package:plugin_toolbox_ui/plugin_toolbox_ui.dart';

import '../../l10n/app_localizations.dart';
import '../providers/app_providers.dart';
import 'store_providers.dart';
import 'store_service.dart';

/// 当前宿主版本号。
///
/// 与 `app/pubspec.yaml`、设置页关于项、`app/test/widget_test.dart` 三处保持同步，
/// 由 `tool/verify.dart` 的版本号一致性断言守护。
/// 商店用它校验插件清单声明的 `minAppVersion`，因此必须与 pubspec 的版本号一致。
const String kHostAppVersion = '0.2.1';

/// 插件分类的中文展示名（未知分类回落到 PluginCategory.other 的标签）。
String pluginCategoryLabel(String categoryName) =>
    PluginCategory.fromString(categoryName).label;

/// 权限名的中文展示名（未登记的权限名原样展示，避免隐藏信息）。
String pluginPermissionLabel(String permissionName) =>
    PluginPermission.fromString(permissionName)?.label ?? permissionName;

/// 分类图标：让商店条目的视觉识别从纯文字升级为"图标 + 文本"双通道
IconData pluginCategoryIcon(String categoryName) {
  switch (PluginCategory.fromString(categoryName)) {
    case PluginCategory.encoding:
      return Icons.swap_horiz_rounded;
    case PluginCategory.generator:
      return Icons.auto_awesome_outlined;
    case PluginCategory.text:
      return Icons.text_fields_rounded;
    case PluginCategory.system:
      return Icons.settings_suggest_outlined;
    case PluginCategory.calculator:
      return Icons.calculate_outlined;
    case PluginCategory.network:
      return Icons.public_rounded;
    case PluginCategory.other:
      return Icons.extension_outlined;
  }
}

/// 插件商店页：浏览远端插件目录并逐个确认安装。
///
/// 版本与简介一律来自远端 `plugin-source/<id>/plugin.json`；安装前会展示
/// 权限、体积与"同 ID 覆盖即更新"的提示，安装完成后立即注册并出现在首页。
class PluginStorePage extends ConsumerStatefulWidget {
  const PluginStorePage({super.key});

  @override
  ConsumerState<PluginStorePage> createState() => _PluginStorePageState();
}

class _PluginStorePageState extends ConsumerState<PluginStorePage> {
  /// 正在下载安装的插件（id -> 显示名），同时用于禁用按钮与渲染进度遮罩
  final Map<String, String> _busyPlugins = {};

  /// 搜索与分类过滤状态
  final TextEditingController _searchController = TextEditingController();
  String _searchKeyword = '';
  String? _selectedCategory;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    ref.invalidate(pluginStoreResolvedRefProvider);
    ref.invalidate(pluginStoreCatalogProvider);
    await ref.read(pluginStoreCatalogProvider.future);
  }

  Future<void> _confirmAndInstall(PluginStoreItem item) async {
    if (_busyPlugins.containsKey(item.id)) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final l10n = AppLocalizations.of(ctx);
        final sensitivePermissions = item.entry.permissions
            .map(PluginPermission.fromString)
            .where((p) => p != null && p.isSensitive)
            .cast<PluginPermission>()
            .toList();

        return AppDialog(
          icon: item.state == PluginStoreInstallState.updateAvailable
              ? Icons.system_update_alt_rounded
              : Icons.download_for_offline_outlined,
          title: item.state == PluginStoreInstallState.updateAvailable
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
              // 弹窗内的元信息卡需显式铺满对话框宽度，
              // 否则 Card 会收缩成内容宽度而显得突兀
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
                          ctx,
                          '分类: ${pluginCategoryLabel(item.entry.category)}',
                        ),
                        _dialogMetaLine(ctx, '作者: ${item.entry.author}'),
                        _dialogMetaLine(
                          ctx,
                          '体积: ${item.entry.packageSizeLabel}',
                        ),
                        _dialogMetaLine(
                          ctx,
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
                  item.state == PluginStoreInstallState.updateAvailable
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
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l10n?.cancel ?? '取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                item.state == PluginStoreInstallState.updateAvailable
                    ? (l10n?.update ?? '更新')
                    : (l10n?.install ?? '安装'),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;
    await _install(item);
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

  Future<void> _install(PluginStoreItem item) async {
    final l10n = AppLocalizations.of(context);
    setState(() => _busyPlugins[item.id] = item.name);

    // 安装期间由页面自身的遮罩层阻断交互并展示进度：
    // 不走额外的 Dialog 路由, 避免与刚关闭的确认对话框抢同一个 Navigator。
    String message;
    bool success = false;
    try {
      final service = ref.read(pluginStoreServiceProvider);
      final outcome = await service.install(item.entry);

      // 同 ID 覆盖即插件更新：注册中心会弃用旧实例并重新初始化
      final registry = ref.read(pluginRegistryProvider);
      final existingPerms = registry.getCustomPermissions(outcome.plugin.id);
      if (existingPerms != null) {
        final merged = Set<PluginPermission>.from(existingPerms)
          ..addAll(outcome.plugin.manifest.permissions);
        registry.setCustomPermissions(outcome.plugin.id, merged);
      }
      registry.register(outcome.plugin);
      await registry.initializePlugin(outcome.plugin.id);
      ref.read(pluginRegistryProvider.notifier).refresh();
      await ref.read(pluginRegistryProvider.notifier).saveOrder();

      success = true;
      final warnings =
          outcome.warnings.isEmpty ? '' : '（${outcome.warnings.join('；')}）';
      final action = item.state == PluginStoreInstallState.updateAvailable
          ? (l10n?.actionUpdated ?? '已更新')
          : (l10n?.actionInstalled ?? '已安装');
      message = l10n?.pluginInstallSuccess(
              item.name, outcome.plugin.version, action, warnings) ??
          '${item.name} v${outcome.plugin.version} $action$warnings';
    } on PluginStoreException catch (e) {
      message = '${item.name}: ${e.message}';
    } on FormatException catch (e) {
      message = l10n?.invalidPackageError(item.name, e.message) ??
          '${item.name}: 安装包无效 (${e.message})';
    } catch (_) {
      message =
          l10n?.installFailedRetry(item.name) ?? '${item.name}: 安装失败，请稍后重试';
    } finally {
      if (mounted) {
        setState(() => _busyPlugins.remove(item.id));
      }
    }

    if (!mounted) return;
    // 失败提示停留更久，便于用户读取具体原因
    if (success) {
      AppSnack.success(context, message);
    } else {
      AppSnack.error(context, message);
    }
    if (success) {
      // 安装态与本地版本已变化, 刷新目录以更新按钮状态
      ref.invalidate(pluginStoreCatalogProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final catalogAsync = ref.watch(pluginStoreCatalogProvider);
    // 仅跟随全量插件列表重建：无关事件不再刷新商店页
    final installedPlugins = ref.watch(allPluginListProvider);
    final service = ref.watch(pluginStoreServiceProvider);

    return PluginPageScaffold(
      title: l10n?.pluginStore ?? '插件商店',
      subtitle: l10n?.storeSubtitle ?? '浏览目录、确认权限后一键安装',
      maxContentWidth: AppLayout.maxContentWidth,
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded),
          tooltip: l10n?.refreshCatalogTooltip ?? '刷新插件目录',
          onPressed: _busyPlugins.isEmpty ? _refresh : null,
        ),
      ],
      body: Stack(
        children: [
          Positioned.fill(
              child: _buildBody(catalogAsync, installedPlugins, service)),
          if (_busyPlugins.isNotEmpty) _buildBusyOverlay(),
        ],
      ),
    );
  }

  Widget _buildBody(
    AsyncValue<PluginStoreCatalog> catalogAsync,
    List<ToolPlugin> installedPlugins,
    PluginStoreService service,
  ) {
    final l10n = AppLocalizations.of(context);
    return catalogAsync.when(
      loading: () => const AppSkeletonList(itemCount: 4),
      error: (error, _) => ErrorView(
        message: error is PluginStoreException
            ? error.message
            : (l10n?.errorCatalogLoadFailed ?? '插件目录加载失败，请检查网络后重试'),
        onRetry: _refresh,
        retryLabel: l10n?.retry ?? '重新加载',
      ),
      data: (catalog) {
        final allItems = service.buildItems(
          catalog: catalog,
          installedPlugins: installedPlugins,
          appVersion: kHostAppVersion,
        );
        if (allItems.isEmpty) {
          return AppEmptyState(
            icon: Icons.storefront_outlined,
            title: l10n?.emptyStoreTitle ?? '远端插件目录为空',
            message:
                l10n?.emptyStoreMessage ?? '当前插件仓库暂无可安装的插件，可稍后重试或在设置中切换仓库。',
            action: FilledButton.tonalIcon(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text(l10n?.retry ?? '重新加载'),
            ),
          );
        }

        final filteredItems = allItems.where((item) {
          if (_selectedCategory != null &&
              item.entry.category != _selectedCategory) {
            return false;
          }
          if (_searchKeyword.isNotEmpty) {
            final kw = _searchKeyword.toLowerCase();
            final matchName = item.name.toLowerCase().contains(kw);
            final matchDesc = item.description.toLowerCase().contains(kw);
            final matchAuthor = item.entry.author.toLowerCase().contains(kw);
            final matchId = item.id.toLowerCase().contains(kw);
            return matchName || matchDesc || matchAuthor || matchId;
          }
          return true;
        }).toList();

        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            itemCount: filteredItems.isEmpty ? 4 : filteredItems.length + 3,
            itemBuilder: (context, index) {
              if (index == 0) return _buildSearchBar();
              if (index == 1) return _buildCategoryChips(allItems);
              if (index == 2) {
                return _buildHeader(catalog, allItems, filteredItems);
              }
              if (filteredItems.isEmpty) return _buildEmptyFilterState();
              return _buildItemCard(filteredItems[index - 3]);
            },
          ),
        );
      },
    );
  }

  Widget _buildSearchBar() {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.xs,
      ),
      child: TextField(
        controller: _searchController,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: l10n?.storeSearchHint ?? '搜索插件名称、描述或作者...',
          prefixIcon: const Icon(Icons.search_rounded, size: 20),
          suffixIcon: _searchKeyword.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  tooltip: l10n?.clearSearchTooltip ?? '清空搜索',
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchKeyword = '');
                  },
                )
              : null,
          filled: true,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm + 2,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            borderSide: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
        ),
        onChanged: (val) => setState(() => _searchKeyword = val.trim()),
      ),
    );
  }

  Widget _buildCategoryChips(List<PluginStoreItem> allItems) {
    final categories = <String>{};
    for (final it in allItems) {
      if (it.entry.category.isNotEmpty) {
        categories.add(it.entry.category);
      }
    }
    if (categories.isEmpty) return const SizedBox.shrink();

    final sortedCats = categories.toList()..sort();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: [
          FilterChip(
            label: Text(AppLocalizations.of(context)?.allFilter ?? '全部'),
            selected: _selectedCategory == null,
            onSelected: (_) => setState(() => _selectedCategory = null),
          ),
          const SizedBox(width: AppSpacing.sm),
          for (final cat in sortedCats) ...[
            FilterChip(
              label: Text(pluginCategoryLabel(cat)),
              selected: _selectedCategory == cat,
              onSelected: (sel) =>
                  setState(() => _selectedCategory = sel ? cat : null),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyFilterState() {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.xxxl,
        horizontal: AppSpacing.xxl,
      ),
      child: AppEmptyState(
        icon: Icons.search_off_rounded,
        title: l10n?.emptyFilterTitle ?? '未找到匹配的插件',
        message: l10n?.emptyFilterMessage ?? '试试更换关键词，或清除当前分类筛选。',
        action: TextButton.icon(
          onPressed: () {
            _searchController.clear();
            setState(() {
              _searchKeyword = '';
              _selectedCategory = null;
            });
          },
          icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
          label: Text(l10n?.clearFilter ?? '清除筛选条件'),
        ),
      ),
    );
  }

  /// 安装进行中的页面级遮罩：阻断重复点击，并展示正在安装的插件名。
  Widget _buildBusyOverlay() {
    final l10n = AppLocalizations.of(context);
    final name = _busyPlugins.length == 1 ? _busyPlugins.values.first : null;
    final scheme = Theme.of(context).colorScheme;
    return Positioned.fill(
      child: IgnorePointer(
        child: ColoredBox(
          color: scheme.shadow.withValues(alpha: 0.45),
          child: Center(
            child: Card(
              margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xxxl),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xl,
                  vertical: AppSpacing.lg,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: AppSpacing.lg),
                    Flexible(
                      child: Text(
                        name == null
                            ? (l10n?.installingPlugin ?? '正在安装插件 …')
                            : (l10n?.downloadingAndInstalling(name) ??
                                '正在下载并安装 $name …'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(
    PluginStoreCatalog catalog,
    List<PluginStoreItem> allItems,
    List<PluginStoreItem> filteredItems,
  ) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final repoConfig = ref.watch(customPluginRepositoryProvider);
    final sourceLabel = repoConfig.summary;
    final countLabel = filteredItems.length == allItems.length
        ? '共 ${allItems.length} 个插件'
        : '共 ${allItems.length} 个插件 (已筛选出 ${filteredItems.length} 个)';
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.xs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                countLabel,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              AppBadge(
                label: _selectedCategory == null
                    ? (l10n?.allCategories ?? '全部分类')
                    : pluginCategoryLabel(_selectedCategory!),
                tone: _selectedCategory == null
                    ? AppBadgeTone.neutral
                    : AppBadgeTone.primary,
                dense: true,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            '来源: $sourceLabel · 版本取自 plugin-source 清单',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (catalog.skipped.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              '${catalog.skipped.length} 个条目元数据不完整已跳过',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildItemCard(PluginStoreItem item) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final busy = _busyPlugins.containsKey(item.id);
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
                      // 名称独占一行：安装态徽标下沉到下一行，
                      // 避免长插件名被徽标与右侧状态挤压成省略号
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
                _buildAction(item, busy, updateAvailable),
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
    PluginStoreItem item,
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
      onPressed: () => _confirmAndInstall(item),
      child: Text(
          updateAvailable ? (l10n?.update ?? '更新') : (l10n?.install ?? '安装')),
    );
  }
}
