import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:plugin_toolbox_ui/plugin_toolbox_ui.dart';
import 'package:reorderable_grid_view/reorderable_grid_view.dart';

import '../../l10n/app_localizations.dart';
import '../providers/app_providers.dart';

/// 工具箱首页：品牌导航 + 已启用插件的可拖拽网格。
///
/// 视觉规范要点：
/// - 图标网格间距与卡片圆角统一取自设计令牌，横竖屏切换时按可用宽度自适应列数；
/// - 空态、加载态、错误态统一使用共享状态组件，避免"没有插件时"页面观感失衡。
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final init = ref.watch(appInitFutureProvider);
    // 仅跟随启用插件列表重建：无关 EventBus 事件不再触发整页刷新
    final plugins = ref.watch(enabledPluginListProvider);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: AppLayout.appBarHeight + AppSpacing.md,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('PluginToolbox'),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              l10n?.myTools ?? '我的工具',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w400,
                  ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.storefront_outlined),
            tooltip: l10n?.pluginStore ?? '插件商店',
            onPressed: () => context.push('/store'),
          ),
          IconButton(
            icon: const Icon(Icons.extension_outlined),
            tooltip: l10n?.pluginManager ?? '插件管理',
            onPressed: () => context.push('/manager'),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: l10n?.settings ?? '设置',
            onPressed: () => context.push('/settings'),
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
      ),
      body: init.when(
        data: (_) {
          if (plugins.isEmpty) {
            // 说明性副文案目前仅有中文版本：英文环境下直接省略，
            // 避免出现中英混排的割裂观感
            final isZh = Localizations.localeOf(context).languageCode == 'zh';
            return AppEmptyState(
              icon: Icons.dashboard_customize_outlined,
              title: l10n?.emptyToolsPrompt ?? '暂无已启用的插件',
              message: isZh ? '安装插件后即可在此快速打开；长按图标可调整排列顺序。' : null,
              action: FilledButton.icon(
                onPressed: () => context.push('/store'),
                icon: const Icon(Icons.shopping_bag_outlined, size: 18),
                label: Text(l10n?.goToStoreToInstall ?? '去插件商店安装'),
              ),
              secondaryAction: TextButton.icon(
                onPressed: () => context.push('/manager'),
                icon: const Icon(Icons.file_upload_outlined, size: 18),
                label: Text(l10n?.importLocalPtx ?? '导入本地 .ptx'),
              ),
            );
          }

          final media = MediaQuery.of(context);
          final isPortrait = media.orientation == Orientation.portrait;

          // 卡片宽高比随可用宽度动态计算：固定值在小屏会挤压文字、
          // 在平板等大屏会过度拉伸留白
          return LayoutBuilder(builder: (context, constraints) {
            final crossAxisCount = AppLayout.gridColumnsFor(
              constraints.maxWidth,
              portrait: isPortrait,
            );
            const horizontalPadding = AppSpacing.lg;
            const crossSpacing = AppSpacing.md;
            final itemWidth = (constraints.maxWidth -
                    horizontalPadding * 2 -
                    crossSpacing * (crossAxisCount - 1)) /
                crossAxisCount;
            // 卡片高度设下限 136dp：保证图标 + 两行标题 + 两行简介在最小屏宽下
            // 仍有余量，避免亚像素级 RenderFlex 溢出；上限用宽度比 1.15 约束，
            // 防止平板多列时卡片被过度拉扁
            final itemHeight =
                (itemWidth / 1.15) < 136 ? 136.0 : itemWidth / 1.15;
            final childAspectRatio = itemWidth / itemHeight;

            return ReorderableGridView.builder(
              padding: const EdgeInsets.fromLTRB(
                horizontalPadding,
                AppSpacing.md,
                horizontalPadding,
                AppSpacing.xxl,
              ),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                mainAxisSpacing: crossSpacing,
                crossAxisSpacing: crossSpacing,
                childAspectRatio: childAspectRatio,
              ),
              itemCount: plugins.length,
              onReorder: (oldIndex, newIndex) async {
                await ref
                    .read(pluginRegistryProvider.notifier)
                    .reorderEnabled(oldIndex, newIndex);
              },
              dragWidgetBuilder: (index, child) {
                return Material(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.xl),
                    side: BorderSide(
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.8),
                      width: 1.5,
                    ),
                  ),
                  elevation: AppElevation.drag,
                  shadowColor: Colors.black.withValues(alpha: 0.6),
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  clipBehavior: Clip.antiAlias,
                  child: child,
                );
              },
              itemBuilder: (context, index) {
                final plugin = plugins[index];
                return PluginCard(
                  key: ValueKey(plugin.id),
                  plugin: plugin,
                  onTap: () => context.push('/plugin/${plugin.routePath}'),
                );
              },
            );
          });
        },
        loading: () => const AppLoadingView(),
        error: (err, _) => ErrorView(message: '加载插件失败: $err'),
      ),
    );
  }
}
