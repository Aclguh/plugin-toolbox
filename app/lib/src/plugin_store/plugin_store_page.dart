import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';
import 'package:plugin_toolbox_ui/plugin_toolbox_ui.dart';

import '../providers/app_providers.dart';
import 'store_providers.dart';
import 'store_service.dart';

/// 当前宿主版本号。
///
/// 与 `app/pubspec.yaml`、设置页关于项、`app/test/widget_test.dart` 三处保持同步，
/// 由 `tool/verify.dart` 的版本号一致性断言守护。
/// 商店用它校验插件清单声明的 `minAppVersion`，因此必须与 pubspec 的版本号一致。
const String kHostAppVersion = '0.2.0';

/// 插件分类的中文展示名（未知分类回落到 PluginCategory.other 的标签）。
String pluginCategoryLabel(String categoryName) =>
    PluginCategory.fromString(categoryName).label;

/// 权限名的中文展示名（未登记的权限名原样展示，避免隐藏信息）。
String pluginPermissionLabel(String permissionName) =>
    PluginPermission.fromString(permissionName)?.label ?? permissionName;

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

  Future<void> _refresh() async {
    ref.invalidate(pluginStoreCatalogProvider);
    await ref.read(pluginStoreCatalogProvider.future);
  }

  Future<void> _confirmAndInstall(PluginStoreItem item) async {
    if (_busyPlugins.containsKey(item.id)) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(item.state == PluginStoreInstallState.updateAvailable
            ? '更新插件'
            : '安装插件'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${item.name} v${item.version}'),
              const SizedBox(height: 8),
              Text(item.description),
              const SizedBox(height: 12),
              Text('分类: ${pluginCategoryLabel(item.entry.category)}'),
              Text('作者: ${item.entry.author}'),
              Text('体积: ${item.entry.packageSizeLabel}'),
              Text(
                '权限: ${item.entry.permissions.isEmpty ? '无' : item.entry.permissions.map(pluginPermissionLabel).join('、')}',
              ),
              if (item.entry.permissions.any((p) => PluginPermission.fromString(p)?.isSensitive ?? false)) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 16,
                      color: Theme.of(ctx).colorScheme.error,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '包含敏感硬件或网络权限，安装后首次使用需谨慎',
                        style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                              color: Theme.of(ctx).colorScheme.error,
                            ),
                      ),
                    ),
                  ],
                ),
              ],
              if (item.installedVersion != null) ...[
                const SizedBox(height: 12),
                Text(
                  item.state == PluginStoreInstallState.updateAvailable
                      ? '将把本地 ${item.installedVersion} 覆盖为 ${item.version}'
                      : '本地已安装 ${item.installedVersion}',
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              item.state == PluginStoreInstallState.updateAvailable ? '更新' : '安装',
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    await _install(item);
  }

  Future<void> _install(PluginStoreItem item) async {
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
      registry.register(outcome.plugin);
      await registry.initializeAll();
      ref.read(pluginRegistryProvider.notifier).refresh();
      await ref.read(pluginRegistryProvider.notifier).saveOrder();

      success = true;
      final warnings = outcome.warnings.isEmpty ? '' : '（${outcome.warnings.join('；')}）';
      message =
          '${item.name} v${outcome.plugin.version} ${item.state == PluginStoreInstallState.updateAvailable ? '已更新' : '已安装'}$warnings';
    } on PluginStoreException catch (e) {
      message = '${item.name}: ${e.message}';
    } on FormatException catch (e) {
      message = '${item.name}: 安装包无效 (${e.message})';
    } catch (_) {
      message = '${item.name}: 安装失败，请稍后重试';
    } finally {
      if (mounted) {
        setState(() => _busyPlugins.remove(item.id));
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: success ? 3 : 4),
      ),
    );
    if (success) {
      // 安装态与本地版本已变化, 刷新目录以更新按钮状态
      ref.invalidate(pluginStoreCatalogProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalogAsync = ref.watch(pluginStoreCatalogProvider);
    final registry = ref.watch(pluginRegistryProvider);
    final service = ref.watch(pluginStoreServiceProvider);

    return PluginPageScaffold(
      title: '插件商店',
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: '刷新插件目录',
          onPressed: _busyPlugins.isEmpty ? _refresh : null,
        ),
      ],
      body: Stack(
        children: [
          Positioned.fill(child: _buildBody(catalogAsync, registry, service)),
          if (_busyPlugins.isNotEmpty) _buildBusyOverlay(),
        ],
      ),
    );
  }

  Widget _buildBody(
    AsyncValue<PluginStoreCatalog> catalogAsync,
    PluginRegistry registry,
    PluginStoreService service,
  ) {
    return catalogAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ErrorView(
                  message: error is PluginStoreException
                      ? error.message
                      : '插件目录加载失败，请检查网络后重试',
                ),
                const SizedBox(height: 16),
                FilledButton.tonal(
                  onPressed: _refresh,
                  child: const Text('重新加载'),
                ),
              ],
            ),
          ),
        ),
        data: (catalog) {
          final items = service.buildItems(
            catalog: catalog,
            installedPlugins: registry.allPlugins,
            appVersion: kHostAppVersion,
          );
          if (items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.storefront_outlined,
                      size: 64,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    const SizedBox(height: 16),
                    const Text('远端插件目录为空'),
                    const SizedBox(height: 12),
                    FilledButton.tonal(
                      onPressed: _refresh,
                      child: const Text('重新加载'),
                    ),
                  ],
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: items.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) return _buildHeader(catalog, items);
                return _buildItemCard(items[index - 1]);
              },
            ),
          );
        },
      );
  }

  /// 安装进行中的页面级遮罩：阻断重复点击，并展示正在安装的插件名。
  Widget _buildBusyOverlay() {
    final name =
        _busyPlugins.length == 1 ? _busyPlugins.values.first : null;
    return Positioned.fill(
      child: IgnorePointer(
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.45),
          child: Center(
            child: Card(
              margin: const EdgeInsets.symmetric(horizontal: 40),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 16),
                    Flexible(
                      child: Text(
                        name == null ? '正在安装插件 …' : '正在下载并安装 $name …',
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

  Widget _buildHeader(PluginStoreCatalog catalog, List<PluginStoreItem> items) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '共 ${items.length} 个插件',
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            '目录来源: $kPluginStoreOwner/$kPluginStoreRepository · 版本信息取自 plugin-source 清单',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (catalog.skipped.isNotEmpty) ...[
            const SizedBox(height: 4),
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
    final theme = Theme.of(context);
    final busy = _busyPlugins.containsKey(item.id);
    final updateAvailable = item.state == PluginStoreInstallState.updateAvailable;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '版本 ${item.version} · ${pluginCategoryLabel(item.entry.category)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _buildAction(item, busy, updateAvailable),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              item.description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '作者 ${item.entry.author} · 体积 ${item.entry.packageSizeLabel} · '
              '权限 ${item.entry.permissions.isEmpty ? '无' : item.entry.permissions.map(pluginPermissionLabel).join('/')}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            if (item.installedVersion != null) ...[
              const SizedBox(height: 4),
              Text(
                '本地已安装 ${item.installedVersion}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
            if (!item.minAppVersionSatisfied) ...[
              const SizedBox(height: 6),
              Text(
                '需要宿主版本 ${item.entry.minAppVersion} 及以上',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAction(
    PluginStoreItem item,
    bool busy,
    bool updateAvailable,
  ) {
    if (busy) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (!item.minAppVersionSatisfied) {
      return Text(
        '版本不满足',
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
            Icons.check,
            size: 16,
            color: Theme.of(context).colorScheme.secondary,
          ),
          const SizedBox(width: 4),
          Text(
            '已是最新',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.secondary,
                ),
          ),
        ],
      );
    }
    return FilledButton.tonal(
      onPressed: () => _confirmAndInstall(item),
      child: Text(updateAvailable ? '更新' : '安装'),
    );
  }
}
