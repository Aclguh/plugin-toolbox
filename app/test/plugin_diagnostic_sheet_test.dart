import 'package:plugin_toolbox/l10n/app_localizations.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:plugin_toolbox/src/plugin_host/plugin_diagnostic_sheet.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late DynamicPlugin mockPlugin;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('diag_sheet_test_');

    const manifest = PluginManifest(
      id: 'diag_tool',
      name: '诊断测试工具',
      version: '2.1.0',
      description: '用于测试诊断面板',
      author: 'Tester',
      type: 'lua',
      category: PluginCategory.system,
      entry: 'main.lua',
      ui: 'ui/main.ui.json',
      permissions: [PluginPermission.storage],
    );

    mockPlugin = DynamicPlugin(
      manifest: manifest,
      rootDir: tempDir,
    );

    final context = PluginContext(
      pluginId: 'diag_tool',
      storage: const PluginStorageFactory().create(
        'diag_tool',
        rootDir: tempDir,
      ),
      eventBus: EventBusImpl(),
      logger: Logger(),
      grantedPermissions: {PluginPermission.storage},
      rootDir: tempDir,
    );

    context.recordLog('测试启动日志第一行');
    context.recordLog('[ERROR] 模拟运行时异常');

    await mockPlugin.initialize(context);
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  testWidgets('PluginDiagnosticSheet 渲染基础信息、权限与控制台日志', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () {
                PluginDiagnosticSheet.show(
                  ctx,
                  plugin: mockPlugin,
                );
              },
              child: const Text('打开诊断面板'),
            ),
          ),
        ),
      ),
    );

    // 点击打开底部抽屉
    await tester.tap(find.text('打开诊断面板'));
    await tester.pumpAndSettle();

    // 验证抽屉标题与基础信息卡片
    expect(find.text('插件诊断与控制台'), findsOneWidget);
    expect(find.text('基础信息与资源占用'), findsOneWidget);
    expect(find.text('diag_tool'), findsOneWidget);
    expect(find.text('2.1.0'), findsOneWidget);
    expect(find.text('系统工具'), findsOneWidget);
    expect(find.text('运行期已获授权'), findsOneWidget);
    expect(find.text('storage'), findsOneWidget);

    // 切换至控制台日志 Tab
    await tester.tap(find.text('控制台日志'));
    await tester.pumpAndSettle();

    // 验证日志条目存在
    expect(find.textContaining('测试启动日志第一行'), findsOneWidget);
    expect(find.textContaining('[ERROR] 模拟运行时异常'), findsOneWidget);
    expect(find.text('共 2 条记录'), findsOneWidget);

    // 清空日志
    await tester.tap(find.text('清空'));
    await tester.pumpAndSettle();

    expect(find.textContaining('暂无控制台日志输出'), findsOneWidget);
  });
  testWidgets('PluginDiagnosticSheet 支持英文国际化渲染', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () {
                PluginDiagnosticSheet.show(
                  ctx,
                  plugin: mockPlugin,
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Plugin Diagnostics & Console'), findsOneWidget);
    expect(find.text('Basic Info & Resource Usage'), findsOneWidget);
    expect(find.text('Granted Permissions'), findsOneWidget);

    await tester.tap(find.text('Console Logs'));
    await tester.pumpAndSettle();

    expect(find.text('2 records total'), findsOneWidget);
    expect(find.text('Copy All'), findsOneWidget);
    expect(find.text('Clear'), findsOneWidget);
  });

  testWidgets('PluginDiagnosticSheet 渲染权限审计记录与空态提示', (tester) async {
    mockPlugin.context?.recordAuditTrail(
      PluginPermission.storage,
      'read_config',
      granted: true,
    );
    mockPlugin.context?.recordAuditTrail(
      PluginPermission.network,
      'http_get',
      granted: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => ElevatedButton(
              onPressed: () {
                PluginDiagnosticSheet.show(
                  ctx,
                  plugin: mockPlugin,
                );
              },
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -300));
    await tester.pumpAndSettle();

    expect(find.text('敏感权限访问审计'), findsOneWidget);
    expect(find.text('ALLOW'), findsOneWidget);
    expect(find.text('DENY'), findsOneWidget);
    expect(find.text('read_config'), findsOneWidget);
    expect(find.text('http_get'), findsOneWidget);
  });
}
