import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:plugin_toolbox_ui/plugin_toolbox_ui.dart';

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
          final categories = registry.pluginsByCategory;
          if (categories.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.dashboard_customize_outlined, size: 64, color: Colors.grey),
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

          return ListView.builder(
            itemCount: categories.length,
            itemBuilder: (context, idx) {
              final cat = categories.keys.elementAt(idx);
              final plugins = categories[cat]!;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionHeader(title: cat.label),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: isPortrait ? 3 : 4,
                      mainAxisSpacing: 10,
                      crossAxisSpacing: 10,
                      childAspectRatio: isPortrait ? 0.80 : 0.95,
                    ),
                    itemCount: plugins.length,
                    itemBuilder: (context, i) {
                      return PluginCard(
                        plugin: plugins[i],
                        onTap: () => context.push('/plugin/${plugins[i].routePath}'),
                      );
                    },
                  ),
                ],
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
