import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (methodCall) async {
        if (methodCall.method == 'getApplicationDocumentsDirectory') {
          return '.';
        }
        return null;
      },
    );
  });

  group('PluginManifest Tests', () {
    test('parses plugin manifest correctly', () {
      final json = {
        'id': 'base64_tool',
        'name': 'Base64 编解码',
        'version': '1.0.0',
        'description': 'Base64 编码与解码工具',
        'author': 'PluginToolbox',
        'type': 'lua',
        'category': 'encoding',
        'permissions': ['clipboard', 'storage'],
        'entry': 'main.lua',
        'ui': 'ui/main.ui.json',
      };

      final manifest = PluginManifest.fromJson(json);

      expect(manifest.id, 'base64_tool');
      expect(manifest.name, 'Base64 编解码');
      expect(manifest.version, '1.0.0');
      expect(manifest.category, PluginCategory.encoding);
      expect(manifest.permissions, contains(PluginPermission.clipboard));
      expect(manifest.permissions, contains(PluginPermission.storage));
      expect(manifest.entry, 'main.lua');
      expect(manifest.ui, 'ui/main.ui.json');
    });

    test('serializes manifest to json', () {
      const manifest = PluginManifest(
        id: 'test_plugin',
        name: 'Test Plugin',
        version: '1.2.3',
        description: 'Testing',
        author: 'Tester',
        type: 'lua',
        category: PluginCategory.calculator,
        permissions: [PluginPermission.clipboard],
        entry: 'entry.lua',
        ui: 'ui.json',
      );

      final json = manifest.toJson();
      expect(json['id'], 'test_plugin');
      expect(json['category'], 'calculator');
      expect(json['permissions'], ['clipboard']);
    });
  });

  group('PluginRegistry & EventBus Tests', () {
    test('registers, enables, disables and unregisters plugins', () async {
      final eventBus = EventBusImpl();
      const storageFactory = PluginStorageFactory();
      final registry = PluginRegistry(
        eventBus: eventBus,
        storageFactory: storageFactory,
      );

      const manifest = PluginManifest(
        id: 'calc_plugin',
        name: 'Calculator',
        version: '1.0.0',
        description: 'Simple Calculator',
        author: 'Dev',
        type: 'lua',
        category: PluginCategory.calculator,
        permissions: [],
        entry: 'main.lua',
        ui: 'main.ui.json',
      );

      final events = <AppEvent>[];
      final sub = eventBus.on<AppEvent>().listen(events.add);

      final plugin = DynamicPlugin(
        manifest: manifest,
        rootDir: Directory('.'),
      );

      registry.register(plugin);
      expect(registry.allPlugins.length, 1);
      expect(registry.isEnabled('calc_plugin'), isTrue);

      await registry.setEnabled('calc_plugin', false);
      expect(registry.isEnabled('calc_plugin'), isFalse);
      expect(registry.enabledPlugins.isEmpty, isTrue);

      await registry.setEnabled('calc_plugin', true);
      expect(registry.isEnabled('calc_plugin'), isTrue);

      await registry.unregister('calc_plugin');
      expect(registry.allPlugins.isEmpty, isTrue);

      await Future.delayed(const Duration(milliseconds: 50));
      expect(events.whereType<PluginStateChangedEvent>().length, 2);
      expect(events.whereType<PluginUninstalledEvent>().length, 1);

      await sub.cancel();
      eventBus.dispose();
    });

    test('same-id re-register re-initializes the new instance (插件更新场景)', () async {
      final registry = PluginRegistry(
        eventBus: EventBusImpl(),
        storageFactory: const PluginStorageFactory(),
      );

      const v1 = PluginManifest(
        id: 'up_plugin',
        name: 'Updater',
        version: '1.0.0',
        description: 'old',
        author: 'Tester',
        type: 'lua',
        category: PluginCategory.calculator,
        permissions: [],
        entry: 'main.lua',
        ui: 'main.ui.json',
      );
      const v2 = PluginManifest(
        id: 'up_plugin',
        name: 'Updater',
        version: '1.1.0',
        description: 'new',
        author: 'Tester',
        type: 'lua',
        category: PluginCategory.calculator,
        permissions: [],
        entry: 'main.lua',
        ui: 'main.ui.json',
      );

      final oldPlugin = DynamicPlugin(manifest: v1, rootDir: Directory('.'));
      final newPlugin = DynamicPlugin(manifest: v2, rootDir: Directory('.'));

      registry.register(oldPlugin);
      await registry.initializeAll();
      expect(oldPlugin.context, isNotNull);
      expect(registry.getPlugin('up_plugin'), same(oldPlugin));

      // 导入新版 .ptx: 同 ID 覆盖注册, initializeAll 必须初始化新实例
      registry.register(newPlugin);
      await registry.initializeAll();

      expect(registry.getPlugin('up_plugin'), same(newPlugin));
      expect(newPlugin.context, isNotNull);
      expect(oldPlugin.context, isNull);
      expect(registry.allPlugins.length, 1);
    });

    test('reorders plugins and preserves order', () async {
      final registry = PluginRegistry(
        eventBus: EventBusImpl(),
        storageFactory: const PluginStorageFactory(),
      );

      const m1 = PluginManifest(
        id: 'p1',
        name: 'P1',
        version: '1.0.0',
        description: 'd1',
        author: 'Tester',
        type: 'lua',
        category: PluginCategory.calculator,
        permissions: [],
        entry: 'e.lua',
        ui: 'u.json',
      );
      const m2 = PluginManifest(
        id: 'p2',
        name: 'P2',
        version: '1.0.0',
        description: 'd2',
        author: 'Tester',
        type: 'lua',
        category: PluginCategory.calculator,
        permissions: [],
        entry: 'e.lua',
        ui: 'u.json',
      );
      const m3 = PluginManifest(
        id: 'p3',
        name: 'P3',
        version: '1.0.0',
        description: 'd3',
        author: 'Tester',
        type: 'lua',
        category: PluginCategory.calculator,
        permissions: [],
        entry: 'e.lua',
        ui: 'u.json',
      );

      registry.register(DynamicPlugin(manifest: m1, rootDir: Directory('.')));
      registry.register(DynamicPlugin(manifest: m2, rootDir: Directory('.')));
      registry.register(DynamicPlugin(manifest: m3, rootDir: Directory('.')));

      expect(registry.allPlugins.map((p) => p.id).toList(), ['p1', 'p2', 'p3']);

      // reorder in all plugins
      registry.reorder(2, 0); // move p3 to start
      expect(registry.allPlugins.map((p) => p.id).toList(), ['p3', 'p1', 'p2']);

      // reorder enabled plugins with some disabled
      await registry.setEnabled('p1', false);
      expect(registry.enabledPlugins.map((p) => p.id).toList(), ['p3', 'p2']);

      registry.reorderEnabled(1, 0); // move p2 before p3
      expect(registry.enabledPlugins.map((p) => p.id).toList(), ['p2', 'p3']);
      expect(registry.allPlugins.map((p) => p.id).toList(), ['p2', 'p3', 'p1']);

      // loadOrder
      registry.loadOrder(['p1', 'p2', 'p3']);
      expect(registry.allPlugins.map((p) => p.id).toList(), ['p1', 'p2', 'p3']);
    });
  });
}
