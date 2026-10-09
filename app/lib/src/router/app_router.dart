import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';

import '../home/home_page.dart';
import '../plugin_manager/plugin_manager_page.dart';
import '../plugin_store/plugin_store_page.dart';
import '../plugin_host/dynamic_plugin_host_page.dart';
import '../settings/settings_page.dart';
import '../providers/app_providers.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    // 非法路由展示品牌化错误页，而非框架默认的无样式错误
    errorBuilder: (context, state) => _RouteNotFoundPage(uri: state.uri.toString()),
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const HomePage(),
      ),
      GoRoute(
        path: '/manager',
        builder: (context, state) => const PluginManagerPage(),
      ),
      GoRoute(
        path: '/store',
        builder: (context, state) => const PluginStorePage(),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsPage(),
      ),
      GoRoute(
        path: '/plugin/:id',
        builder: (context, state) {
          final pluginId = state.pathParameters['id']!;
          final registry = ref.read(pluginRegistryProvider);
          final plugin = registry.getPlugin(pluginId);
          if (plugin == null) {
            return Scaffold(
              appBar: AppBar(title: const Text('插件未找到')),
              body: Center(child: Text('未找到 ID 为 [$pluginId] 的插件')),
            );
          }
          if (!registry.isEnabled(pluginId)) {
            return Scaffold(
              appBar: AppBar(title: Text(plugin.name)),
              body: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.block_outlined,
                        size: 64,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '插件已停用',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '该插件当前处于禁用状态。如需使用，请前往插件管理中心重新启用。',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: 20),
                      FilledButton.tonal(
                        onPressed: () => context.go('/manager'),
                        child: const Text('前往插件管理'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }
          if (plugin is DynamicPlugin) {
            if (!registry.isInitialized(pluginId)) {
              registry.initializePlugin(pluginId);
            }
            return DynamicPluginHostPage(plugin: plugin);
          }
          // 内置插件页面
          return Scaffold(
            appBar: AppBar(title: Text(plugin.name)),
            body: const Center(child: Text('内置插件展示页')),
          );
        },
      ),
    ],
  );
});

/// 非法路由的品牌化"页面未找到"界面
class _RouteNotFoundPage extends StatelessWidget {
  final String uri;

  const _RouteNotFoundPage({required this.uri});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('页面未找到')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.explore_off_outlined,
              size: 64,
              color: Theme.of(context).colorScheme.outline,
            ),
            const SizedBox(height: 16),
            const Text('要访问的页面不存在'),
            const SizedBox(height: 8),
            Text(
              uri,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: () => context.go('/'),
              child: const Text('返回工具箱首页'),
            ),
          ],
        ),
      ),
    );
  }
}
