import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_toolbox/src/plugin_host/dynamic_plugin_host_page.dart';
import 'package:plugin_toolbox/src/plugin_store/store_service.dart';
import 'package:plugin_toolbox/src/providers/app_providers.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _E2EFakeStoreSource implements PluginStoreSource {
  final List<PluginStoreEntry> entries;
  final Map<String, Uint8List> packages;

  _E2EFakeStoreSource({
    required this.entries,
    required this.packages,
  });

  @override
  Future<PluginStoreCatalog> fetchCatalog() async {
    return PluginStoreCatalog(
      entries: entries,
      revision: 'e2e-rev-1',
      fetchedAt: DateTime(2026, 1, 1),
    );
  }

  @override
  Future<Uint8List> downloadPackage(PluginStoreEntry entry) async {
    final bytes = packages[entry.id];
    if (bytes == null) {
      throw PluginStoreException('安装包不存在: ${entry.id}');
    }
    return bytes;
  }
}

Uint8List _createE2EPtx({
  required String id,
  required String name,
}) {
  final archive = Archive();

  void addFile(String path, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(path, bytes.length, bytes));
  }

  addFile(
    'plugin.json',
    json.encode({
      'id': id,
      'name': name,
      'version': '1.0.0',
      'description': 'E2E 全链路闭环测试插件',
      'author': 'E2E Tester',
      'minAppVersion': '0.1.0',
      'type': 'lua',
      'category': 'utility',
      'permissions': ['storage'],
      'entry': 'main.lua',
      'ui': 'ui/main.ui.json',
      'persistentStates': ['saved_counter'],
    }),
  );

  addFile(
    'main.lua',
    '''
function onInit()
  local current = state.get("saved_counter") or 0
  state.set("saved_counter", current + 1)
  state.set("ready_banner", "E2E_READY")
end
''',
  );

  addFile(
    'ui/main.ui.json',
    json.encode({
      'type': 'Column',
      'props': {
        'persistentStates': ['saved_counter'],
      },
      'children': [
        {
          'type': 'Text',
          'props': {
            'text': '状态: {{state.ready_banner}}',
          },
        },
        {
          'type': 'Text',
          'props': {
            'text': '计数: {{state.saved_counter}}',
          },
        },
      ],
    }),
  );

  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('插件全生命周期闭环 E2E 集成测试', () {
    late Directory tempRoot;
    late Directory pluginsDir;
    late Directory tempDownloadDir;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      tempRoot = Directory.systemTemp.createTempSync('e2e_plugin_test_');
      pluginsDir = Directory('${tempRoot.path}/plugins')..createSync();
      tempDownloadDir = Directory('${tempRoot.path}/tmp')..createSync();
    });

    tearDown(() {
      try {
        if (tempRoot.existsSync()) {
          tempRoot.deleteSync(recursive: true);
        }
      } catch (_) {}
    });

    testWidgets('商店拉取 -> 解包安装 -> 容器挂载运行 -> 状态持久化 -> 页面卸载 -> 沙箱彻底清除',
        (WidgetTester tester) async {
      const pluginId = 'e2e_counter_tool';
      const pluginName = 'E2E 计数器';

      // 1. 模拟商店源与条目
      final ptxBytes = _createE2EPtx(id: pluginId, name: pluginName);
      const storeEntry = PluginStoreEntry(
        id: pluginId,
        name: pluginName,
        version: '1.0.0',
        description: 'E2E 全链路闭环测试插件',
        author: 'E2E Tester',
        category: 'utility',
        permissions: ['storage'],
        packageName: '$pluginId.ptx',
        packageSizeBytes: 2048,
        packageApiUrl: 'https://example.com/e2e.ptx',
        manifestApiUrl: 'https://example.com/plugin.json',
        sourcePath: 'plugin-source/$pluginId',
      );

      final fakeSource = _E2EFakeStoreSource(
        entries: [storeEntry],
        packages: {pluginId: ptxBytes},
      );

      final storeService = PluginStoreService(
        source: fakeSource,
        temporaryDirectoryProvider: () async => tempDownloadDir,
        installer: (file) => PluginInstaller.installFromPtx(
          file,
          baseDirectory: pluginsDir,
        ),
      );

      // 2. 从商店下载并解压安装到沙箱 (Isolate.run 需在真实异步区域执行)
      final outcome =
          (await tester.runAsync(() => storeService.install(storeEntry)))!;
      expect(outcome.plugin.id, equals(pluginId));
      expect(outcome.plugin.name, equals(pluginName));
      expect(outcome.plugin.rootDir.existsSync(), isTrue);

      // 3. 将安装产物注册并初始化到 PluginRegistry
      final prefs = await SharedPreferences.getInstance();
      final bus = EventBusImpl();
      final uninstallSub = PluginInstaller.listenUninstallRequests(
        bus,
        baseDirectory: pluginsDir,
      );
      addTearDown(uninstallSub.cancel);

      final registry = PluginRegistry(
        eventBus: bus,
        storageFactory: const PluginStorageFactory(),
      );
      registry.register(outcome.plugin);

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          pluginRegistryProvider.overrideWith(
            (ref) => PluginRegistryNotifier(registry, prefs, eventBus: bus),
          ),
        ],
      );
      addTearDown(container.dispose);

      // 4. 挂载宿主容器 DynamicPluginHostPage 并驱动 UI 渲染
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: DynamicPluginHostPage(plugin: outcome.plugin),
          ),
        ),
      );

      // 等待异步 IO 与 Lua 引擎完成初始化
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }

      // 验证 UI 成功渲染 Lua 脚本初始化的状态
      expect(find.text(pluginName), findsOneWidget);
      expect(find.text('状态: E2E_READY'), findsOneWidget);
      expect(find.text('计数: 1'), findsOneWidget);

      // 5. 卸载页面，触发 DynamicPluginHostPage.dispose 与 storage.flush()
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Text('已退出插件')),
        ),
      );
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }

      // 6. 验证持久化状态已真正落盘至插件沙箱存储
      final storageFile = File('${outcome.plugin.rootDir.path}/storage.json');
      expect(storageFile.existsSync(), isTrue);
      final savedJson =
          json.decode(storageFile.readAsStringSync()) as Map<String, dynamic>;
      expect(savedJson['saved_counter'], equals(1));

      // 7. 注销插件（注册中心自动触发 EventBus 卸载事件，安装器清理沙箱）
      await registry.unregister(pluginId);
      for (var i = 0; i < 20; i++) {
        if (!outcome.plugin.rootDir.existsSync()) break;
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
      }

      // 8. 验证插件沙箱与持久化数据已被彻底清除
      expect(outcome.plugin.rootDir.existsSync(), isFalse);
      expect(registry.getPlugin(pluginId), isNull);
    });
  });
}
