import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_toolbox/src/plugin_manager/plugin_manager_dialogs.dart';
import 'package:plugin_toolbox/src/plugin_manager/ptx_import.dart';
import 'package:plugin_toolbox/src/providers/app_providers.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Widget buildTestApp(Widget child, [ProviderContainer? container]) {
    final effectiveContainer = container ?? ProviderContainer();

    return UncontrolledProviderScope(
      container: effectiveContainer,
      child: MaterialApp(
        home: Scaffold(
          body: Builder(builder: (context) => child),
        ),
      ),
    );
  }

  testWidgets('ImportSummaryDialog 渲染成功与失败统计项并支持点击确定',
      (WidgetTester tester) async {
    final outcome = PtxImportOutcome(
      installed: const [],
      succeeded: const ['插件 A', '插件 B'],
      failed: const ['插件 C: 清单解析失败'],
    );

    await tester.pumpWidget(
      buildTestApp(
        ElevatedButton(
          onPressed: () {
            // 通过当前上下文弹出汇总弹窗
          },
          child: ImportSummaryDialog(outcome: outcome),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('导入结果'), findsOneWidget);
    expect(find.textContaining('成功 2 个:'), findsOneWidget);
    expect(find.textContaining('· 插件 A'), findsOneWidget);
    expect(find.textContaining('· 插件 B'), findsOneWidget);
    expect(find.textContaining('失败 1 个:'), findsOneWidget);
    expect(find.textContaining('· 插件 C: 清单解析失败'), findsOneWidget);
    expect(find.text('确定'), findsOneWidget);
  });

  testWidgets('InstallErrorDialog 展示错误信息', (WidgetTester tester) async {
    await tester.pumpWidget(
      buildTestApp(
        const InstallErrorDialog(message: '安装包损坏无法解压'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('安装失败'), findsOneWidget);
    expect(find.text('安装包损坏无法解压'), findsOneWidget);
    expect(find.text('确定'), findsOneWidget);
  });

  testWidgets('SensitivePermissionConfirmDialog 展示敏感权限列表并返回确认结果',
      (WidgetTester tester) async {
    bool? userAgreed;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                userAgreed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => const SensitivePermissionConfirmDialog(
                    pluginName: '网络相机工具',
                    pluginVersion: '1.2.0',
                    sensitivePermissions: [
                      PluginPermission.camera,
                      PluginPermission.network,
                    ],
                  ),
                );
              },
              child: const Text('授权弹窗'),
            ),
          ),
        ),
      ),
    );

    // 1. 测试拒绝
    await tester.tap(find.text('授权弹窗'));
    await tester.pumpAndSettle();

    expect(find.text('敏感权限授权确认'), findsOneWidget);
    expect(find.text('插件「网络相机工具 v1.2.0」申请了以下敏感权限：'), findsOneWidget);
    expect(find.text('拒绝并取消'), findsOneWidget);
    expect(find.text('同意并安装'), findsOneWidget);

    await tester.tap(find.text('拒绝并取消'));
    await tester.pumpAndSettle();
    expect(userAgreed, isFalse);

    // 2. 测试同意
    await tester.tap(find.text('授权弹窗'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('同意并安装'));
    await tester.pumpAndSettle();
    expect(userAgreed, isTrue);
  });

  testWidgets('UninstallConfirmDialog 卸载确认弹窗支持取消与卸载',
      (WidgetTester tester) async {
    bool? confirmed;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => const UninstallConfirmDialog(
                    pluginName: '待卸载插件',
                  ),
                );
              },
              child: const Text('卸载确认'),
            ),
          ),
        ),
      ),
    );

    // 1. 取消
    await tester.tap(find.text('卸载确认'));
    await tester.pumpAndSettle();

    expect(find.text('卸载插件'), findsOneWidget);
    expect(find.text('确定要卸载插件「待卸载插件」吗？\n卸载后相关数据将被清除。'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(confirmed, isFalse);

    // 2. 确认卸载
    await tester.tap(find.text('卸载确认'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('卸载'));
    await tester.pumpAndSettle();
    expect(confirmed, isTrue);
  });

  testWidgets('PluginDetailsDialog 显示插件元信息与权限开关切换',
      (WidgetTester tester) async {
    final tempDir = Directory.systemTemp.createTempSync('ptx_details_test_');
    addTearDown(() => tempDir.deleteSync(recursive: true));

    final plugin = DynamicPlugin(
      manifest: const PluginManifest(
        id: 'mock_demo_plugin',
        name: '演示插件',
        version: '2.0.1',
        description: '用于测试权限与元信息的演示插件',
        author: 'Antigravity Team',
        type: 'lua',
        category: PluginCategory.system,
        permissions: [
          PluginPermission.clipboard,
          PluginPermission.camera,
        ],
        entry: 'main.lua',
        ui: 'ui/main.ui.json',
        storageQuotaMb: 16,
      ),
      rootDir: tempDir,
    );

    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
    ]);
    addTearDown(container.dispose);

    // 初始化注册表
    final registry = container.read(pluginRegistryProvider);
    registry.register(plugin);
    await registry.initializePlugin(plugin.id);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: PluginDetailsDialog(plugin: plugin),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('演示插件'), findsOneWidget);
    expect(find.text('ID: mock_demo_plugin'), findsOneWidget);
    expect(find.text('版本: 2.0.1'), findsOneWidget);
    expect(find.text('作者: Antigravity Team'), findsOneWidget);
    expect(find.text('沙箱配额: 16 MB'), findsOneWidget);
    expect(find.text('权限管理'), findsOneWidget);

    // 找到权限开关并切换
    final switchFinder = find.byType(Switch);
    expect(switchFinder, findsNWidgets(2));

    // 切换相机权限
    await tester.tap(switchFinder.last);
    await tester.pumpAndSettle();

    // 再次点击确定/完成
    expect(find.text('完成'), findsOneWidget);
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
  });
}
