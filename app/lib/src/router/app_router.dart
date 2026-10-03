import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';

import '../home/home_page.dart';
import '../plugin_manager/plugin_manager_page.dart';
import '../plugin_host/dynamic_plugin_host_page.dart';
import '../settings/settings_page.dart';
import '../providers/app_providers.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
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
          if (plugin is DynamicPlugin) {
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
