import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:plugin_toolbox/src/app.dart';
import 'package:plugin_toolbox/src/providers/app_providers.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('全链路端到端集成: 插件展示 -> 容器进入与交互 -> 返回与排序持久化', (tester) async {
    // 1. 初始化隔离状态
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    final tempDir = Directory.systemTemp.createTempSync('e2e_mock_plugin_');
    addTearDown(() {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    final uiFile = File('${tempDir.path}/ui.json');
    uiFile.writeAsStringSync('{"type": "Center", "child": {"type": "Text", "text": "插件运行中"}}');

    final entryFile = File('${tempDir.path}/main.lua');
    entryFile.writeAsStringSync('-- mock entry script');

    final mockPlugin = DynamicPlugin(
      manifest: const PluginManifest(
        id: 'e2e_tool',
        name: '端到端测试工具',
        version: '1.0.0',
        description: '用于全链路集成测试的轻量插件',
        author: 'E2E Tester',
        type: 'lua',
        category: PluginCategory.other,
        permissions: [],
        entry: 'main.lua',
        ui: 'ui.json',
      ),
      rootDir: tempDir,
    );

    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        appInitFutureProvider.overrideWith((ref) async {}),
      ],
    );
    addTearDown(container.dispose);

    final registry = container.read(pluginRegistryProvider);
    registry.register(mockPlugin);

    // 2. 挂载应用根组件
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const PluginToolboxApp(),
      ),
    );
    await tester.pumpAndSettle();

    // 3. 验证主页网格成功展示插件卡片与主页标题
    expect(find.text('PluginToolbox'), findsOneWidget);
    expect(find.text('端到端测试工具'), findsOneWidget);

    // 4. 点击进入插件宿主容器
    await tester.tap(find.text('端到端测试工具'));
    await tester.pumpAndSettle();

    // 5. 验证宿主容器页面挂载成功并展示插件标题
    expect(find.text('端到端测试工具'), findsWidgets);

    // 6. 点击返回按钮返回主页
    final backButton = find.byType(BackButton);
    if (backButton.evaluate().isNotEmpty) {
      await tester.tap(backButton.first);
    } else {
      final iconBack = find.byIcon(Icons.arrow_back);
      if (iconBack.evaluate().isNotEmpty) {
        await tester.tap(iconBack.first);
      }
    }
    await tester.pumpAndSettle();

    // 7. 验证已返回主页，插件网格与标题依然正常
    expect(find.text('PluginToolbox'), findsOneWidget);
    expect(find.text('端到端测试工具'), findsOneWidget);

    // 8. 触发插件排序并验证持久化
    final listNotifier = container.read(pluginRegistryProvider.notifier);
    await listNotifier.reorder(0, 0);
    expect(prefs.containsKey('plugin_toolbox_plugin_order'), isTrue);
  });
}
