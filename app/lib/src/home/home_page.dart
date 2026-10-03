import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:plugin_toolbox_ui/plugin_toolbox_ui.dart';
import 'package:reorderable_grid_view/reorderable_grid_view.dart';

import '../providers/app_providers.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final init = ref.watch(appInitFutureProvider);
    final registry = ref.watch(pluginRegistryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('PluginToolbox'),
        actions: [
          IconButton(
            icon: const Icon(Icons.extension_outlined),
            tooltip: '插件管理',
            onPressed: () => context.push('/manager'),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: '设置',
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: init.when(
        data: (_) {
          final plugins = registry.enabledPlugins;
          if (plugins.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.dashboard_customize_outlined,
                    size: 64,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(height: 16),
                  const Text('暂无已启用的插件'),
                  const SizedBox(height: 12),
                  FilledButton.tonal(
                    onPressed: () => context.push('/manager'),
                    child: const Text('去插件中心导入'),
                  ),
                ],
              ),
            );
          }

          final isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;

          return ReorderableGridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: isPortrait ? 3 : 4,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: isPortrait ? 0.80 : 0.95,
            ),
            itemCount: plugins.length,
            onReorder: (oldIndex, newIndex) async {
              await ref.read(pluginRegistryProvider.notifier).reorderEnabled(oldIndex, newIndex);
            },
            dragWidgetBuilder: (index, child) {
              return Material(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
                    width: 1.5,
                  ),
                ),
                elevation: 8,
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
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => ErrorView(message: '加载插件失败: $err'),
      ),
    );
  }
}
