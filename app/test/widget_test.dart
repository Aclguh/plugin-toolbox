import 'package:plugin_toolbox/src/plugin_manager/plugin_manager_dialogs.dart';
import 'package:logger/logger.dart';
import 'package:plugin_toolbox/l10n/app_localizations_en.dart';
import 'package:plugin_toolbox/l10n/app_localizations_zh.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_toolbox/src/app.dart';
import 'package:plugin_toolbox/src/home/home_page.dart';
import 'package:plugin_toolbox/src/plugin_manager/plugin_manager_page.dart';
import 'package:plugin_toolbox/src/router/app_router.dart';
import 'package:plugin_toolbox/src/settings/settings_page.dart';
import 'package:plugin_toolbox/src/providers/app_providers.dart';
import 'package:plugin_toolbox/src/plugin_host/dynamic_plugin_host_page.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';
import 'package:plugin_toolbox/l10n/app_localizations.dart';
import 'package:reorderable_grid_view/reorderable_grid_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 创建已注入 mock SharedPreferences 的测试容器 (状态隔离, 无跨用例残留)
Future<ProviderContainer> createContainer({
  List<Override> overrides = const [],
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(overrides: [
    sharedPreferencesProvider.overrideWithValue(prefs),
    ...overrides,
  ]);
  addTearDown(container.dispose);
  return container;
}

final _mockRootDir = Directory.systemTemp.createTempSync('mock_plugin_test_');

ToolPlugin createMockPlugin(String id, String name) {
  return DynamicPlugin(
    manifest: PluginManifest(
      id: id,
      name: name,
      version: '1.0.0',
      description: 'Description for $name',
      author: 'Tester',
      type: 'lua',
      category: PluginCategory.calculator,
      permissions: [],
      entry: 'entry.lua',
      ui: 'ui.json',
    ),
    rootDir: _mockRootDir,
  );
}

class _MockBuiltinPlugin extends ToolPlugin {
  @override
  String get id => 'builtin_p';
  @override
  String get name => '内置测试插件';
  @override
  String get description => '内置插件不可删除';
  @override
  String get version => '1.0.0';
  @override
  PluginCategory get category => PluginCategory.other;
  @override
  bool get isDynamic => false;
  @override
  Future<void> initialize(PluginContext context) async {}
  @override
  Future<void> dispose() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('App launches and renders title smoke test',
      (WidgetTester tester) async {
    final container = await createContainer(overrides: [
      appInitFutureProvider.overrideWith((ref) async {}),
    ]);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const PluginToolboxApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('PluginToolbox'), findsOneWidget);
  });

  testWidgets('HomePage 提供插件商店入口, 点击跳转 /store', (WidgetTester tester) async {
    final container = await createContainer(overrides: [
      appInitFutureProvider.overrideWith((ref) async {}),
    ]);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: HomePage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 空态主页给出商店入口 + 本地导入入口
    expect(find.text('去插件商店安装'), findsOneWidget);
    expect(find.text('导入本地 .ptx'), findsOneWidget);

    final storeButton = find.byIcon(Icons.storefront_outlined);
    expect(storeButton, findsOneWidget);
    expect(
      find.ancestor(of: storeButton, matching: find.byType(IconButton)),
      findsOneWidget,
    );
  });

  testWidgets(
      'HomePage renders plugins in ReorderableGridView without category headers',
      (WidgetTester tester) async {
    final container = await createContainer(
      overrides: [
        appInitFutureProvider.overrideWith((ref) async {}),
      ],
    );
    final registry = container.read(pluginRegistryProvider);
    registry.register(createMockPlugin('p1', 'Plugin 1'));
    registry.register(createMockPlugin('p2', 'Plugin 2'));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: HomePage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify plugins are displayed
    expect(find.text('Plugin 1'), findsOneWidget);
    expect(find.text('Plugin 2'), findsOneWidget);

    // Verify ReorderableGridView is used and configured with rounded-corner dragWidgetBuilder
    final gridView =
        tester.widget<ReorderableGridView>(find.byType(ReorderableGridView));
    expect(gridView.dragWidgetBuilderV2, isNotNull);
    final dragWidget =
        gridView.dragWidgetBuilderV2!.builder(0, const SizedBox(), null);
    expect(dragWidget, isA<Material>());
    final material = dragWidget as Material;
    expect(material.shape, isA<RoundedRectangleBorder>());
    final shape = material.shape as RoundedRectangleBorder;
    expect((shape.borderRadius as BorderRadius).topLeft.x, 16.0);
    expect(material.elevation, 8.0);

    // Verify NO category SectionHeaders are present
    expect(find.text(PluginCategory.calculator.label), findsNothing);
  });

  testWidgets(
      'PluginManagerPage has left drag handle, switch, no trash icon, and long-press delete dialog',
      (WidgetTester tester) async {
    final container = await createContainer();
    final registry = container.read(pluginRegistryProvider);
    registry.register(createMockPlugin('p1', 'Plugin 1'));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: PluginManagerPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify ReorderableListView has rounded proxyDecorator
    final listView =
        tester.widget<ReorderableListView>(find.byType(ReorderableListView));
    expect(listView.proxyDecorator, isNotNull);

    // Verify drag indicator icon on left
    expect(find.byIcon(Icons.drag_indicator), findsOneWidget);

    // Verify ReorderableDelayedDragStartListener is present
    expect(find.byType(ReorderableDelayedDragStartListener), findsOneWidget);

    // Verify switch is present
    expect(find.byType(Switch), findsOneWidget);

    // Verify trash can icon is removed
    expect(find.byIcon(Icons.delete_outline), findsNothing);

    // Long press on card body to trigger delete confirmation dialog
    await tester.longPress(find.text('Plugin 1'));
    await tester.pumpAndSettle();

    // Verify delete confirmation dialog appeared
    expect(find.text('卸载插件'), findsOneWidget);
    expect(find.text('确定要卸载插件「Plugin 1」吗？\n卸载后相关数据将被清除。'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('卸载'), findsOneWidget);

    // Tap cancel to dismiss dialog
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(find.text('卸载插件'), findsNothing);

    // 点击插件卡片打开详情与权限管理弹窗
    await tester.tap(find.text('Plugin 1'));
    await tester.pumpAndSettle();

    expect(find.text('权限管理'), findsOneWidget);
    expect(find.text('完成'), findsOneWidget);

    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(find.text('权限管理'), findsNothing);
  });

  testWidgets('批量导入: 逐文件安装, 单文件失败不影响其余, 结果可汇总', (WidgetTester tester) async {
    // 扩展名过滤
    expect(isPtxPackage('a.ptx'), isTrue);
    expect(isPtxPackage('a.PTX'), isTrue);
    expect(isPtxPackage('a.zip'), isTrue);
    expect(isPtxPackage('a.txt'), isFalse);
    expect(isPtxPackage('noext'), isFalse);

    Future<DynamicPlugin> fakeInstaller(File file) async {
      final name = file.uri.pathSegments.last;
      if (name == 'broken.ptx') {
        throw const FormatException('安装包中未找到 plugin.json 清单文件');
      }
      if (name == 'boom.ptx') {
        throw Exception('unexpected');
      }
      return DynamicPlugin(
        manifest: PluginManifest(
          id: name.split('.').first,
          name: name,
          version: '1.1.0',
          description: 'd',
          author: 'Tester',
          type: 'lua',
          category: PluginCategory.generator,
          permissions: [],
          entry: 'main.lua',
          ui: 'ui/main.ui.json',
        ),
        rootDir: _mockRootDir,
      );
    }

    final outcome = await importPtxFiles(
      files: [
        PlatformFile(name: 'ok1.ptx', size: 10, path: '/tmp/ok1.ptx'),
        PlatformFile(name: 'notes.txt', size: 10, path: '/tmp/notes.txt'),
        PlatformFile(name: 'no_path.ptx', size: 0),
        PlatformFile(name: 'broken.ptx', size: 10, path: '/tmp/broken.ptx'),
        PlatformFile(name: 'boom.ptx', size: 10, path: '/tmp/boom.ptx'),
        PlatformFile(name: 'ok2.ptx', size: 10, path: '/tmp/ok2.ptx'),
      ],
      installer: fakeInstaller,
    );

    // 成功 2 个, 失败 4 个 (含扩展名/路径缺失/安装异常/未知异常)
    expect(outcome.succeeded, ['ok1.ptx v1.1.0', 'ok2.ptx v1.1.0']);
    expect(outcome.installed.length, 2);
    expect(outcome.failed.length, 4);
    expect(outcome.failed[0], contains('仅支持 .ptx 或 .zip'));
    expect(outcome.failed[1], contains('无法读取文件'));
    expect(outcome.failed[2], contains('未找到 plugin.json'));
    expect(outcome.failed[3], contains('未知错误'));
  });

  testWidgets('Order is synchronized between HomePage and PluginManagerPage',
      (WidgetTester tester) async {
    final container = await createContainer();
    final registry = container.read(pluginRegistryProvider);
    final notifier = container.read(pluginRegistryProvider.notifier);

    registry.register(createMockPlugin('p1', 'Plugin 1'));
    registry.register(createMockPlugin('p2', 'Plugin 2'));
    registry.register(createMockPlugin('p3', 'Plugin 3'));

    expect(registry.allPlugins.map((p) => p.id).toList(), ['p1', 'p2', 'p3']);
    expect(
        registry.enabledPlugins.map((p) => p.id).toList(), ['p1', 'p2', 'p3']);

    // Reorder from Manager (move p3 to index 0)
    await notifier.reorder(2, 0);
    expect(registry.allPlugins.map((p) => p.id).toList(), ['p3', 'p1', 'p2']);
    expect(
        registry.enabledPlugins.map((p) => p.id).toList(), ['p3', 'p1', 'p2']);

    // Reorder from Home (move p2 to index 0)
    await notifier.reorderEnabled(2, 0);
    expect(registry.allPlugins.map((p) => p.id).toList(), ['p2', 'p3', 'p1']);
    expect(
        registry.enabledPlugins.map((p) => p.id).toList(), ['p2', 'p3', 'p1']);
  });

  testWidgets(
      'SettingsPage allows changing theme mode and toggling dynamic color',
      (WidgetTester tester) async {
    final container = await createContainer();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: SettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('外观与显示'), findsOneWidget);
    expect(find.text('主题模式'), findsOneWidget);
    expect(find.text('动态取色 (Material You)'), findsOneWidget);
    expect(find.text('品牌深色（默认）'), findsOneWidget);

    // 版本号第三处同步断言: 与 pubspec.yaml (0.2.1+3) 保持一致
    expect(find.textContaining('版本 0.2.1'), findsOneWidget);
  });

  testWidgets('SettingsPage 支持自定义插件仓库配置与重置为默认', (WidgetTester tester) async {
    final container = await createContainer();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: SettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('自定义插件仓库'), findsOneWidget);
    expect(find.text('当前: Aclguh/PTX-plugins（官方默认）'), findsOneWidget);

    // 点击打开自定义插件仓库对话框
    await tester.tap(find.text('自定义插件仓库'));
    await tester.pumpAndSettle();

    expect(find.text('GitHub 仓库链接'), findsOneWidget);

    // 点击取消
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    // 再次打开
    await tester.tap(find.text('自定义插件仓库'));
    await tester.pumpAndSettle();

    // 输入非法内容保存，应提示错误
    await tester.enterText(find.byType(TextField), 'invalid_single_token');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('请输入有效的 GitHub 仓库链接，例如：owner/repo'), findsOneWidget);

    // 点击清除按钮
    await tester.tap(find.byIcon(Icons.clear));
    await tester.pumpAndSettle();

    // 保存空内容恢复默认
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    // 再次打开并输入合法链接保存
    await tester.tap(find.text('自定义插件仓库'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byType(TextField), 'https://github.com/custom-team/cool-plugins');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(find.text('当前: custom-team/cool-plugins'), findsOneWidget);

    // 再次点击打开，验证多源列表并点击快速切换
    await tester.tap(find.text('自定义插件仓库'));
    await tester.pumpAndSettle();

    expect(find.textContaining('已订阅的源'), findsOneWidget);
    await tester.tap(find.textContaining('官方默认').last);
    await tester.pumpAndSettle();

    // 移除源
    await tester.tap(find.byIcon(Icons.close).last);
    await tester.pumpAndSettle();

    expect(find.text('恢复默认'), findsOneWidget);
    await tester.tap(find.text('恢复默认'));
    await tester.pumpAndSettle();

    expect(find.text('当前: Aclguh/PTX-plugins（官方默认）'), findsOneWidget);
  });

  testWidgets('SettingsPage 点击关于展示全量软件信息（包名、GitHub 仓库、开源许可等）',
      (WidgetTester tester) async {
    final container = await createContainer();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: SettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 点击关于项
    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('版本 0.2.1'));
    await tester.pumpAndSettle();

    // 验证全量软件信息展示
    expect(find.text('com.plugintoolbox.plugin_toolbox'), findsOneWidget);
    expect(
        find.text('https://github.com/Aclguh/plugin-toolbox'), findsOneWidget);
    expect(find.text('MIT License'), findsOneWidget);
    expect(find.text('核心架构'), findsOneWidget);
    expect(find.text('开发团队'), findsOneWidget);
    expect(find.text('复制信息'), findsOneWidget);

    // 点击复制信息
    await tester.tap(find.text('复制信息'));
    await tester.pumpAndSettle();

    // 点击查看协议
    await tester.tap(find.text('查看协议'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Permission is hereby granted'), findsOneWidget);

    // 点击复制协议
    await tester.tap(find.text('复制协议'));
    await tester.pumpAndSettle();

    // 关闭协议弹窗 (顶层对话框)
    await tester.tap(find.text('关闭').last);
    await tester.pumpAndSettle();

    // 关闭关于详情弹窗
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
  });

  testWidgets(
      'DynamicPluginHostPage handles missing UI file with graceful ErrorView',
      (WidgetTester tester) async {
    final mockPlugin = createMockPlugin('missing_ui', '测试插件');
    final container = await createContainer();

    // 宿主页经 ConsumerState 读取注册表完成懒初始化，需注入 ProviderScope
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: DynamicPluginHostPage(plugin: mockPlugin as DynamicPlugin),
        ),
      ),
    );

    // 宿主页对 UI 描述的读取是真实异步 IO (H-2 移除了同步阻塞读),
    // fake-async 测试环境需要 runAsync 留出真实事件循环窗口
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();

    // 验证 AppBar 标题为插件名称
    expect(find.text('测试插件'), findsOneWidget);
    // 验证当 UI 描述文件缺失时，宿主容器安全降级展示错误视图，而不是崩溃
    expect(find.textContaining('插件运行错误'), findsOneWidget);
  });

  testWidgets('DynamicPluginHostPage 点击返回按钮安全退出页面',
      (WidgetTester tester) async {
    final mockPlugin = createMockPlugin('back_test', '返回测试');
    final container = await createContainer();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => DynamicPluginHostPage(
                            plugin: mockPlugin as DynamicPlugin),
                      ),
                    );
                  },
                  child: const Text('打开插件'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开插件'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();

    expect(find.text('返回测试'), findsOneWidget);

    final backButton = find.byType(BackButton);
    expect(backButton, findsOneWidget);
    await tester.tap(backButton);
    await tester.pumpAndSettle();

    expect(find.text('打开插件'), findsOneWidget);
    expect(find.text('返回测试'), findsNothing);
  });

  testWidgets('非法路由展示品牌化的页面未找到错误页', (WidgetTester tester) async {
    final container = await createContainer(overrides: [
      appInitFutureProvider.overrideWith((ref) async {}),
    ]);
    final router = container.read(appRouterProvider);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    router.go('/definitely/not/exist');
    await tester.pumpAndSettle();

    expect(find.text('页面未找到'), findsOneWidget);
    expect(find.text('要访问的页面不存在'), findsOneWidget);
    expect(find.text('返回工具箱首页'), findsOneWidget);
  });

  testWidgets('访问已停用插件路由展示停用提示页', (WidgetTester tester) async {
    final mockPlugin = createMockPlugin('disabled_p', '已停用插件');
    final container = await createContainer(overrides: [
      appInitFutureProvider.overrideWith((ref) async {}),
    ]);
    final registry = container.read(pluginRegistryProvider);
    registry.register(mockPlugin);
    await registry.setEnabled('disabled_p', false);

    final router = container.read(appRouterProvider);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    router.go('/plugin/disabled_p');
    await tester.pumpAndSettle();

    expect(find.text('插件已停用'), findsOneWidget);
    expect(find.text('前往插件管理'), findsOneWidget);
  });

  testWidgets('通过路由直达未初始化的动态插件时自愈初始化并安全展示', (WidgetTester tester) async {
    final mockPlugin = createMockPlugin('deep_link_p', '直达插件');
    final container = await createContainer(overrides: [
      appInitFutureProvider.overrideWith((ref) async {}),
    ]);
    final registry = container.read(pluginRegistryProvider);
    registry.register(mockPlugin);
    expect(registry.isInitialized('deep_link_p'), isFalse);

    final router = container.read(appRouterProvider);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    router.go('/plugin/deep_link_p');
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();

    expect(registry.isInitialized('deep_link_p'), isTrue);
    expect(find.text('直达插件'), findsOneWidget);
  });

  testWidgets('路由 extra 贯通至宿主页 initialData（plugin.open 调起参数）',
      (WidgetTester tester) async {
    final mockPlugin = createMockPlugin('extra_p', '参数插件');
    final container = await createContainer(overrides: [
      appInitFutureProvider.overrideWith((ref) async {}),
    ]);
    final registry = container.read(pluginRegistryProvider);
    registry.register(mockPlugin);

    final router = container.read(appRouterProvider);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    // 模拟 plugin.open 调起：extra 携带初始参数
    unawaited(router
        .push('/plugin/extra_p', extra: {'source': 'unit_test', 'value': 42}));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();

    final hostPage = tester
        .widget<DynamicPluginHostPage>(find.byType(DynamicPluginHostPage));
    expect(hostPage.initialData, {'source': 'unit_test', 'value': 42});
  });

  test('派生 provider：无关 EventBus 事件不触发列表重建，排序双端同源同步', () async {
    final container = await createContainer();
    final registry = container.read(pluginRegistryProvider);
    final notifier = container.read(pluginRegistryProvider.notifier);

    registry.register(createMockPlugin('p1', 'Plugin 1'));
    registry.register(createMockPlugin('p2', 'Plugin 2'));
    registry.register(createMockPlugin('p3', 'Plugin 3'));
    notifier.refresh();

    final allBefore = container.read(allPluginListProvider);
    final enabledBefore = container.read(enabledPluginListProvider);

    var allNotify = 0, enabledNotify = 0;
    container.listen(allPluginListProvider, (_, __) => allNotify++);
    container.listen(enabledPluginListProvider, (_, __) => enabledNotify++);

    // 无关事件（注册表缓存未失效）不应触发任何派生 provider 通知
    // (container.listen 的回调异步调度，需留出真实事件循环窗口)
    container.read(eventBusProvider).fire(PluginStateChangedEvent('p1', true));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(allNotify, 0);
    expect(enabledNotify, 0);
    expect(container.read(allPluginListProvider), same(allBefore));
    expect(container.read(enabledPluginListProvider), same(enabledBefore));

    // 排序变更：全量与启用列表同源同步更新
    await notifier.reorder(2, 0);
    await Future<void>.delayed(Duration.zero);
    expect(allNotify, greaterThan(0));
    expect(enabledNotify, greaterThan(0));
    expect(container.read(allPluginListProvider).map((p) => p.id).toList(),
        ['p3', 'p1', 'p2']);
    expect(container.read(enabledPluginListProvider).map((p) => p.id).toList(),
        ['p3', 'p1', 'p2']);

    // 启禁用变更：启用列表联动收缩，与全量列表保持同一数据源
    await notifier.setEnabled('p1', false);
    await Future<void>.delayed(Duration.zero);
    expect(registry.isEnabled('p1'), isFalse);
    expect(container.read(enabledPluginListProvider).map((p) => p.id).toList(),
        ['p3', 'p2']);
    expect(container.read(allPluginListProvider).map((p) => p.id).toList(),
        ['p3', 'p1', 'p2']);
  });

  testWidgets('PluginRegistryNotifier 启用停用与自定义权限持久化',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      appInitFutureProvider.overrideWith((ref) async {}),
    ]);
    addTearDown(container.dispose);

    final notifier = container.read(pluginRegistryProvider.notifier);
    final registry = container.read(pluginRegistryProvider);
    final mockPlugin = createMockPlugin('perm_p', '权限测试插件');
    registry.register(mockPlugin);

    // 设置停用并持久化
    await notifier.setEnabled('perm_p', false);
    expect(registry.disabledPluginIds, contains('perm_p'));
    expect(prefs.getStringList('plugin_toolbox_disabled_plugins'),
        contains('perm_p'));

    // 设置自定义权限并持久化
    await notifier.setCustomPermissions('perm_p', {PluginPermission.camera});
    expect(registry.getCustomPermissions('perm_p'),
        contains(PluginPermission.camera));
    expect(
      prefs.getStringList('plugin_toolbox_permissions_perm_p'),
      contains('camera'),
    );

    // 重新启用
    await notifier.setEnabled('perm_p', true);
    expect(registry.disabledPluginIds.contains('perm_p'), isFalse);
    expect(prefs.getStringList('plugin_toolbox_disabled_plugins'), isEmpty);
  });

  testWidgets('多语言国际化：切换英文 Locale 渲染对应英文文本', (tester) async {
    final container = await createContainer(overrides: [
      appInitFutureProvider.overrideWith((ref) async {}),
    ]);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: HomePage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No enabled tools yet'), findsOneWidget);
    expect(find.text('Install from Store'), findsOneWidget);
    expect(find.text('Import local .ptx'), findsOneWidget);
  });

  test('AppLocalizations 多语言实体属性完整性', () {
    final zh = AppLocalizationsZh();
    expect(zh.appTitle, isNotEmpty);
    expect(zh.myTools, isNotEmpty);
    expect(zh.pluginStore, isNotEmpty);
    expect(zh.pluginManager, isNotEmpty);
    expect(zh.settings, isNotEmpty);
    expect(zh.appearanceAndDisplay, isNotEmpty);
    expect(zh.themeMode, isNotEmpty);
    expect(zh.themeDark, isNotEmpty);
    expect(zh.themeLight, isNotEmpty);
    expect(zh.themeSystem, isNotEmpty);
    expect(zh.dynamicColor, isNotEmpty);
    expect(zh.dynamicColorDesc, isNotEmpty);
    expect(zh.autoRotateScreen, isNotEmpty);
    expect(zh.autoRotateScreenDesc, isNotEmpty);
    expect(zh.about, isNotEmpty);
    expect(zh.aboutApp, isNotEmpty);
    expect(zh.aboutDesc, isNotEmpty);
    expect(zh.author, isNotEmpty);
    expect(zh.openSourceLicense, isNotEmpty);
    expect(zh.openSourceLicenseDesc, isNotEmpty);
    expect(zh.install, isNotEmpty);
    expect(zh.update, isNotEmpty);
    expect(zh.uninstall, isNotEmpty);
    expect(zh.cancel, isNotEmpty);
    expect(zh.confirm, isNotEmpty);
    expect(zh.searchHint, isNotEmpty);
    expect(zh.emptyToolsPrompt, isNotEmpty);
    expect(zh.emptyToolsMessage, isNotEmpty);
    expect(zh.goToStoreToInstall, isNotEmpty);
    expect(zh.importLocalPtx, isNotEmpty);

    final en = AppLocalizationsEn();
    expect(en.appTitle, isNotEmpty);
    expect(en.myTools, isNotEmpty);
    expect(en.pluginStore, isNotEmpty);
    expect(en.pluginManager, isNotEmpty);
    expect(en.settings, isNotEmpty);
    expect(en.appearanceAndDisplay, isNotEmpty);
    expect(en.themeMode, isNotEmpty);
    expect(en.themeDark, isNotEmpty);
    expect(en.themeLight, isNotEmpty);
    expect(en.themeSystem, isNotEmpty);
    expect(en.dynamicColor, isNotEmpty);
    expect(en.dynamicColorDesc, isNotEmpty);
    expect(en.autoRotateScreen, isNotEmpty);
    expect(en.autoRotateScreenDesc, isNotEmpty);
    expect(en.about, isNotEmpty);
    expect(en.aboutApp, isNotEmpty);
    expect(en.aboutDesc, isNotEmpty);
    expect(en.author, isNotEmpty);
    expect(en.openSourceLicense, isNotEmpty);
    expect(en.openSourceLicenseDesc, isNotEmpty);
    expect(en.install, isNotEmpty);
    expect(en.update, isNotEmpty);
    expect(en.uninstall, isNotEmpty);
    expect(en.cancel, isNotEmpty);
    expect(en.confirm, isNotEmpty);
    expect(en.searchHint, isNotEmpty);
    expect(en.emptyToolsPrompt, isNotEmpty);
    expect(en.emptyToolsMessage, isNotEmpty);
    expect(en.goToStoreToInstall, isNotEmpty);
    expect(en.importLocalPtx, isNotEmpty);
  });

  testWidgets('PluginManagerPage 渲染插件列表、启禁用开关与删除二次确认流程', (tester) async {
    final container = await createContainer(overrides: [
      appInitFutureProvider.overrideWith((ref) async {}),
    ]);
    final registry = container.read(pluginRegistryProvider);
    final mockPlugin = createMockPlugin('mgr_p1', '管理测试插件');
    final builtinPlugin = _MockBuiltinPlugin();
    registry.register(mockPlugin);
    registry.register(builtinPlugin);
    container.read(pluginRegistryProvider.notifier).refresh();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: PluginManagerPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('插件管理中心'), findsOneWidget);
    expect(find.text('管理测试插件'), findsOneWidget);

    final switchFinder = find.byType(Switch);
    expect(switchFinder, findsNWidgets(2));
    await tester.tap(switchFinder.first);
    await tester.pumpAndSettle();
    expect(registry.isEnabled('mgr_p1'), isFalse);

    await tester.tap(switchFinder.first);
    await tester.pumpAndSettle();
    expect(registry.isEnabled('mgr_p1'), isTrue);

    await tester.longPress(find.text('管理测试插件'));
    await tester.pumpAndSettle();
    expect(find.text('卸载插件'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('卸载插件'), findsNothing);
    expect(registry.getPlugin('mgr_p1'), isNotNull);

    await tester.longPress(find.text('管理测试插件'));
    await tester.pumpAndSettle();
    expect(find.text('卸载插件'), findsOneWidget);
    // 对话框内的卸载按钮
    await tester.tap(find.widgetWithText(FilledButton, '卸载'));
    await tester.pumpAndSettle();
    expect(registry.getPlugin('mgr_p1'), isNull);

    // 点击卡片打开详情弹窗并关闭
    await tester.tap(find.text('内置测试插件'));
    await tester.pumpAndSettle();
    expect(find.byType(PluginDetailsDialog), findsOneWidget);
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(find.byType(PluginDetailsDialog), findsNothing);

    // 长按内置插件提示不可删除
    ScaffoldMessenger.of(tester.element(find.byType(PluginManagerPage)))
        .clearSnackBars();
    await tester.pumpAndSettle();
    await tester.longPress(find.text('内置测试插件'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('内置插件无法删除'), findsOneWidget);

    // 卸载全部插件后展示空态提示
    await registry.unregister('builtin_p');
    container.read(pluginRegistryProvider.notifier).refresh();
    await tester.pumpAndSettle();
    expect(find.text('暂无插件，点击右下角按钮导入'), findsOneWidget);
  });

  testWidgets('DynamicPluginHostPage 页面容器与诊断控制台弹窗挂载', (tester) async {
    final tempDir = Directory.systemTemp.createTempSync('host_page_test_');
    addTearDown(() {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    final entryFile = File('${tempDir.path}/entry.lua');
    entryFile.writeAsStringSync('function onInit() end');
    final uiFile = File('${tempDir.path}/ui.json');
    uiFile.writeAsStringSync('{"type": "Text", "text": "插件运行中"}');

    final dynamicPlugin = DynamicPlugin(
      manifest: const PluginManifest(
        id: 'host_test_p',
        name: '宿主容器测试插件',
        version: '1.0.0',
        description: '',
        author: '',
        type: 'lua',
        category: PluginCategory.other,
        permissions: [],
        entry: 'entry.lua',
        ui: 'ui.json',
      ),
      rootDir: tempDir,
    );

    final container = await createContainer(overrides: [
      appInitFutureProvider.overrideWith((ref) async {}),
    ]);
    final registry = container.read(pluginRegistryProvider);
    registry.register(dynamicPlugin);
    await dynamicPlugin.initialize(PluginContext(
      pluginId: 'host_test_p',
      storage:
          PluginFileStorageImpl(namespace: 'host_test_p', rootDir: tempDir),
      eventBus: EventBusImpl(),
      logger: Logger(),
      grantedPermissions: {},
      rootDir: tempDir,
    ));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: DynamicPluginHostPage(plugin: dynamicPlugin),
        ),
      ),
    );
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('宿主容器测试插件'), findsOneWidget);
    expect(find.byIcon(Icons.bug_report_outlined), findsOneWidget);

    await tester.tap(find.byIcon(Icons.bug_report_outlined));
    for (int i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('插件诊断与控制台'), findsOneWidget);
  });

  testWidgets('PluginManager 弹窗组件族交互与状态渲染', (WidgetTester tester) async {
    // 1. ImportSummaryDialog
    final outcome = PtxImportOutcome(
      installed: [],
      succeeded: ['plugin_a', 'plugin_b'],
      failed: ['plugin_c: 损坏的压缩包'],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImportSummaryDialog(outcome: outcome),
        ),
      ),
    );
    expect(find.text('导入结果'), findsOneWidget);
    expect(find.textContaining('成功 2 个:'), findsOneWidget);
    expect(find.textContaining('失败 1 个:'), findsOneWidget);

    // 2. InstallErrorDialog
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: InstallErrorDialog(message: '包签名损坏'),
        ),
      ),
    );
    expect(find.text('安装失败'), findsOneWidget);
    expect(find.text('包签名损坏'), findsOneWidget);

    // 3. SensitivePermissionConfirmDialog
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SensitivePermissionConfirmDialog(
            pluginName: '网络探针',
            pluginVersion: '2.0.0',
            sensitivePermissions: [PluginPermission.network],
          ),
        ),
      ),
    );
    expect(find.text('敏感权限授权确认'), findsOneWidget);
    expect(find.textContaining('网络探针 v2.0.0'), findsOneWidget);
    expect(find.text('拒绝并取消'), findsOneWidget);
    expect(find.text('同意并安装'), findsOneWidget);

    // 4. PluginDetailsDialog 包含声明权限与敏感权限，且可切换 Switch
    final container = await createContainer();
    final tempDir = Directory.systemTemp.createTempSync('details_dialog_test_');
    addTearDown(() {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });
    final dynPlugin = DynamicPlugin(
      manifest: const PluginManifest(
        id: 'sens_plugin',
        name: '敏感插件',
        version: '1.2.0',
        description: '测试权限切换',
        author: 'SecurityTester',
        type: 'lua',
        category: PluginCategory.network,
        permissions: [PluginPermission.network, PluginPermission.storage],
        entry: 'entry.lua',
        ui: 'ui.json',
      ),
      rootDir: tempDir,
    );
    final pluginContext = PluginContext(
      pluginId: 'sens_plugin',
      storage:
          PluginFileStorageImpl(namespace: 'sens_plugin', rootDir: tempDir),
      eventBus: EventBusImpl(),
      logger: Logger(),
      grantedPermissions: {PluginPermission.network},
      rootDir: tempDir,
    );
    await dynPlugin.initialize(pluginContext);
    container.read(pluginRegistryProvider).register(dynPlugin);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: PluginDetailsDialog(plugin: dynPlugin),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('敏感插件'), findsOneWidget);
    expect(find.text('权限管理'), findsOneWidget);
    expect(find.text('敏感'), findsOneWidget);
    expect(find.byType(SwitchListTile), findsNWidgets(2));

    // 切换权限开关
    await tester.tap(find.byType(SwitchListTile).first);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(SwitchListTile).last);
    await tester.pumpAndSettle();

    expect(find.text('完成'), findsOneWidget);
  });
}
