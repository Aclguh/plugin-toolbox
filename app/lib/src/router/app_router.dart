import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';
import 'package:plugin_toolbox_ui/plugin_toolbox_ui.dart';

import '../home/home_page.dart';
import '../plugin_manager/plugin_manager_page.dart';
import '../plugin_store/plugin_store_page.dart';
import '../plugin_host/dynamic_plugin_host_page.dart';
import '../settings/settings_page.dart';
import '../providers/app_providers.dart';

/// 统一页面转场：与主题内的 [PageTransitionsTheme] 保持同一套缓动，
/// 使 `push`（go_router）与 `Navigator` 两条路径的观感一致。
Page<void> _buildPage(GoRouterState state, Widget child) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: AppMotion.slow,
    reverseTransitionDuration: AppMotion.normal,
    transitionsBuilder: (context, animation, secondaryAnimation, child) =>
        AppPageTransitions.fadeThrough(animation, secondaryAnimation, child),
  );
}

final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    // 非法路由展示品牌化错误页，而非框架默认的无样式错误
    errorBuilder: (context, state) =>
        _RouteNotFoundPage(uri: state.uri.toString()),
    routes: [
      GoRoute(
        path: '/',
        pageBuilder: (context, state) => _buildPage(state, const HomePage()),
      ),
      GoRoute(
        path: '/manager',
        pageBuilder: (context, state) =>
            _buildPage(state, const PluginManagerPage()),
      ),
      GoRoute(
        path: '/store',
        pageBuilder: (context, state) =>
            _buildPage(state, const PluginStorePage()),
      ),
      GoRoute(
        path: '/settings',
        pageBuilder: (context, state) =>
            _buildPage(state, const SettingsPage()),
      ),
      GoRoute(
        path: '/plugin/:id',
        pageBuilder: (context, state) {
          final pluginId = state.pathParameters['id']!;
          final registry = ref.read(pluginRegistryProvider);
          final plugin = registry.getPlugin(pluginId);
          if (plugin == null) {
            return _buildPage(
              state,
              _PluginMessagePage(
                title: '插件未找到',
                icon: Icons.extension_off_outlined,
                message: '未找到 ID 为 [$pluginId] 的插件',
                actionLabel: '返回工具箱首页',
                onAction: () => context.go('/'),
              ),
            );
          }
          if (!registry.isEnabled(pluginId)) {
            return _buildPage(
              state,
              _PluginMessagePage(
                title: plugin.name,
                icon: Icons.block_outlined,
                emptyTitle: '插件已停用',
                message: '该插件当前处于禁用状态。如需使用，请前往插件管理中心重新启用。',
                actionLabel: '前往插件管理',
                onAction: () => context.go('/manager'),
              ),
            );
          }
          if (plugin is DynamicPlugin) {
            // 插件上下文的懒初始化收敛在宿主页面 initState 内，
            // builder 保持纯函数不做副作用，避免路由重建时重复触发初始化；
            // state.extra 携带 plugin.open 调起的初始参数，贯通至宿主页面
            final extra = state.extra;
            final initialData =
                extra is Map ? Map<String, dynamic>.from(extra) : null;
            return _buildPage(
              state,
              DynamicPluginHostPage(
                plugin: plugin,
                initialData: initialData,
              ),
            );
          }
          // 内置插件页面
          return _buildPage(
            state,
            _PluginMessagePage(
              title: plugin.name,
              icon: Icons.widgets_outlined,
              emptyTitle: '内置插件',
              message: '该插件由宿主内置提供，暂无可展示的独立界面。',
              actionLabel: '返回工具箱首页',
              onAction: () => context.go('/'),
            ),
          );
        },
      ),
    ],
  );
});

/// 插件路由降级页：未找到 / 已停用 / 内置占位共用同一套品牌化空态
class _PluginMessagePage extends StatelessWidget {
  final String title;
  final IconData icon;
  final String message;
  final String? emptyTitle;
  final String actionLabel;
  final VoidCallback onAction;

  const _PluginMessagePage({
    required this.title,
    required this.icon,
    required this.message,
    required this.actionLabel,
    required this.onAction,
    this.emptyTitle,
  });

  @override
  Widget build(BuildContext context) {
    return PluginPageScaffold(
      title: title,
      body: AppEmptyState(
        icon: icon,
        title: emptyTitle ?? title,
        message: message,
        action: FilledButton.tonal(
          onPressed: onAction,
          child: Text(actionLabel),
        ),
      ),
    );
  }
}

/// 非法路由的品牌化"页面未找到"界面
class _RouteNotFoundPage extends StatelessWidget {
  final String uri;

  const _RouteNotFoundPage({required this.uri});

  @override
  Widget build(BuildContext context) {
    return PluginPageScaffold(
      title: '页面未找到',
      body: AppEmptyState(
        icon: Icons.explore_off_outlined,
        title: '要访问的页面不存在',
        message: uri,
        action: FilledButton.tonal(
          onPressed: () => context.go('/'),
          child: const Text('返回工具箱首页'),
        ),
      ),
    );
  }
}
