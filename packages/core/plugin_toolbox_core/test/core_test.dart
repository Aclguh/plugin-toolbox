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
  });
}
