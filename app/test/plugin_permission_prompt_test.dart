import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:plugin_toolbox/src/plugin_host/plugin_permission_prompt.dart';
import 'package:plugin_toolbox/src/providers/app_providers.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late DynamicPlugin mockPlugin;
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    tempDir = await Directory.systemTemp.createTemp('jit_perm_test_');

    const manifest = PluginManifest(
      id: 'camera_tool',
      name: '相机工具',
      version: '1.0.0',
      description: '测试相机工具',
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

    await mockPlugin.initialize(PluginContext(
      pluginId: 'camera_tool',
      storage: const PluginStorageFactory().create(
        'camera_tool',
        rootDir: tempDir,
      ),
      eventBus: EventBusImpl(),
      logger: Logger(),
      grantedPermissions: {PluginPermission.storage},
      rootDir: tempDir,
    ));
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  testWidgets('已有权限时直接返回 true 且不弹出对话框', (tester) async {
    late bool result;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                ref.read(pluginRegistryProvider).register(mockPlugin);
                return ElevatedButton(
                  onPressed: () async {
                    result = await PluginPermissionPrompt.requestPermission(
                      context,
                      plugin: mockPlugin,
                      permission: PluginPermission.storage,
                      ref: ref,
                    );
                  },
                  child: const Text('Request'),
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Request'));
    await tester.pump();

    expect(result, isTrue);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('未授权时弹出 Material 3 对话框，点击拒绝返回 false', (tester) async {
    bool? result;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                ref.read(pluginRegistryProvider).register(mockPlugin);
                return ElevatedButton(
                  onPressed: () async {
                    result = await PluginPermissionPrompt.requestPermission(
                      context,
                      plugin: mockPlugin,
                      permission: PluginPermission.camera,
                      ref: ref,
                    );
                  },
                  child: const Text('Request Camera'),
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Request Camera'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('权限申请提示'), findsOneWidget);
    expect(find.text('拒绝'), findsOneWidget);

    await tester.tap(find.text('拒绝'));
    await tester.pumpAndSettle();

    expect(result, isFalse);
    expect(mockPlugin.context?.hasPermission(PluginPermission.camera), isFalse);
  });

  testWidgets('未授权时弹出 Material 3 对话框，点击允许动态授权并持久化', (tester) async {
    bool? result;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                ref.read(pluginRegistryProvider).register(mockPlugin);
                return ElevatedButton(
                  onPressed: () async {
                    result = await PluginPermissionPrompt.requestPermission(
                      context,
                      plugin: mockPlugin,
                      permission: PluginPermission.camera,
                      ref: ref,
                    );
                  },
                  child: const Text('Request Camera'),
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Request Camera'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('允许'), findsOneWidget);

    await tester.tap(find.text('允许'));
    await tester.pumpAndSettle();

    expect(result, isTrue);
    expect(mockPlugin.context?.hasPermission(PluginPermission.camera), isTrue);

    // 检查持久化落盘
    final saved = prefs.getStringList('plugin_toolbox_permissions_camera_tool');
    expect(saved, contains('camera'));
  });
}
