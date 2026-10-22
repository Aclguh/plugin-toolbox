import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_toolbox/src/home/home_page.dart';
import 'package:plugin_toolbox/src/plugin_manager/plugin_manager_page.dart';
import 'package:plugin_toolbox/src/providers/app_providers.dart';
import 'package:plugin_toolbox/src/settings/settings_page.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 小屏响应式回归测试。
///
/// 目标不是校验业务数据，而是守住"布局不溢出"这条硬性门槛：
/// 320x568 属于当前仍在服役的最小移动端视口，任何页面在此尺寸下
/// 出现 `RenderFlex overflowed` 都会以异常形式被断言捕获。
void main() {
  final rootDir = Directory.systemTemp.createTempSync('responsive_test_');

  Future<ProviderContainer> createContainer() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      appInitFutureProvider.overrideWith((ref) async {}),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  ToolPlugin mockPlugin(String id, String name) {
    return DynamicPlugin(
      manifest: PluginManifest(
        id: id,
        name: name,
        version: '1.0.0',
        description: 'Description for $name',
        author: 'Tester',
        type: 'lua',
        category: PluginCategory.calculator,
        permissions: const [],
        entry: 'entry.lua',
        ui: 'ui.json',
      ),
      rootDir: rootDir,
    );
  }

  Future<void> pumpAt(
    WidgetTester tester,
    Size size,
    Widget child, {
    List<Override> overrides = const [],
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = await createContainer();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: child),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('小屏首页空态无布局溢出', (tester) async {
    await pumpAt(tester, const Size(320, 568), const HomePage());

    expect(tester.takeException(), isNull);
    expect(find.text('去插件商店安装'), findsOneWidget);
    expect(find.text('导入本地 .ptx'), findsOneWidget);
  });

  testWidgets('小屏首页多插件网格无布局溢出', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = await createContainer();
    final registry = container.read(pluginRegistryProvider);
    for (var i = 1; i <= 6; i++) {
      registry.register(mockPlugin('p$i', '插件 $i'));
    }
    container.read(pluginRegistryProvider.notifier).refresh();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('插件 1'), findsOneWidget);
  });

  testWidgets('小屏设置页分组卡片无布局溢出', (tester) async {
    await pumpAt(tester, const Size(320, 568), const SettingsPage());

    expect(tester.takeException(), isNull);
    expect(find.text('外观与显示'), findsOneWidget);
    expect(find.text('品牌深色（默认）'), findsOneWidget);
  });

  testWidgets('小屏插件管理中心空态无布局溢出', (tester) async {
    await pumpAt(tester, const Size(320, 568), const PluginManagerPage());

    expect(tester.takeException(), isNull);
    expect(find.text('暂无插件，点击右下角按钮导入'), findsOneWidget);
  });
}
