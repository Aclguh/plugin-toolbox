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
    rootDir: Directory('.'),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('App launches and renders title smoke test', (WidgetTester tester) async {
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

  testWidgets('HomePage renders plugins in ReorderableGridView without category headers',
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
    final gridView = tester.widget<ReorderableGridView>(find.byType(ReorderableGridView));
    expect(gridView.dragWidgetBuilderV2, isNotNull);
    final dragWidget = gridView.dragWidgetBuilderV2!.builder(0, const SizedBox(), null);
    expect(dragWidget, isA<Material>());
    final material = dragWidget as Material;
    expect(material.shape, isA<RoundedRectangleBorder>());
    final shape = material.shape as RoundedRectangleBorder;
    expect((shape.borderRadius as BorderRadius).topLeft.x, 16.0);
    expect(material.elevation, 8.0);

    // Verify NO category SectionHeaders are present
    expect(find.text(PluginCategory.calculator.label), findsNothing);
  });

  testWidgets('PluginManagerPage has left drag handle, switch, no trash icon, and long-press delete dialog',
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
    final listView = tester.widget<ReorderableListView>(find.byType(ReorderableListView));
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

  testWidgets('批量导入: 逐文件安装, 单文件失败不影响其余, 结果可汇总',
      (WidgetTester tester) async {
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
        rootDir: Directory('.'),
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
    expect(registry.enabledPlugins.map((p) => p.id).toList(), ['p1', 'p2', 'p3']);

    // Reorder from Manager (move p3 to index 0)
    await notifier.reorder(2, 0);
    expect(registry.allPlugins.map((p) => p.id).toList(), ['p3', 'p1', 'p2']);
    expect(registry.enabledPlugins.map((p) => p.id).toList(), ['p3', 'p1', 'p2']);

    // Reorder from Home (move p2 to index 0)
    await notifier.reorderEnabled(2, 0);
    expect(registry.allPlugins.map((p) => p.id).toList(), ['p2', 'p3', 'p1']);
    expect(registry.enabledPlugins.map((p) => p.id).toList(), ['p2', 'p3', 'p1']);
  });

  testWidgets('SettingsPage allows changing theme mode and toggling dynamic color',
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

    // 版本号第三处同步断言: 与 pubspec.yaml (0.2.0+2) 保持一致
    expect(find.textContaining('版本 0.2.0'), findsOneWidget);
  });

  testWidgets('DynamicPluginHostPage handles missing UI file with graceful ErrorView',
      (WidgetTester tester) async {
    final mockPlugin = createMockPlugin('missing_ui', '测试插件');

    await tester.pumpWidget(
      MaterialApp(
        home: DynamicPluginHostPage(plugin: mockPlugin as DynamicPlugin),
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

  testWidgets('非法路由展示品牌化的页面未找到错误页', (WidgetTester tester) async {    final container = await createContainer(overrides: [
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
}
