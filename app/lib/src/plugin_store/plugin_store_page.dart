import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';
import 'package:plugin_toolbox_ui/plugin_toolbox_ui.dart';

import '../../l10n/app_localizations.dart';
import '../providers/app_providers.dart';
import 'store_providers.dart';
import 'plugin_store_card.dart';
import 'store_install_confirm_dialog.dart';
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

  // 商店页区分"安装 / 更新 / 已是最新"三种安装态，由 PluginStoreCard 与确认弹窗呈现
  Future<void> _confirmAndInstall(PluginStoreItem item) async {
    if (_busyPlugins.containsKey(item.id)) return;

    final confirmed = await StoreInstallConfirmDialog.show(context, item);
    if (confirmed != true || !mounted) return;
    await _install(item);
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
              final item = filteredItems[index - 3];
              return PluginStoreCard(
                key: ValueKey(item.id),
                item: item,
                isBusy: _busyPlugins.containsKey(item.id),
                onAction: () => _confirmAndInstall(item),
              );
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
        ? (l10n?.totalPluginsCount(allItems.length) ??
            '共 ${allItems.length} 个插件')
        : (l10n?.filteredPluginsCount(allItems.length, filteredItems.length) ??
            '共 ${allItems.length} 个插件 (已筛选出 ${filteredItems.length} 个)');
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
            l10n?.storeSourceHeader(sourceLabel) ??
                '来源: $sourceLabel · 版本取自 plugin-source 清单',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (catalog.skipped.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              l10n?.skippedIncompleteEntries(catalog.skipped.length) ??
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
}
