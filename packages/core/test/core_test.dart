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

    test('AppEvent 具有正确的 Equatable 值对象等价语义 (P3-1)', () {
      final now = DateTime.now();
      final event1 = PluginInstalledEvent('p1', timestamp: now);
      final event2 = PluginInstalledEvent('p1', timestamp: now.add(const Duration(seconds: 1)));
      final event3 = PluginInstalledEvent('p2');

      // 相同业务载荷 (pluginId) 判等为 true，即使发生时刻 timestamp 不同
      expect(event1, equals(event2));
      expect(event1 == event2, isTrue);
      expect(event1 == event3, isFalse);

      final state1 = PluginStateChangedEvent('p1', true);
      final state2 = PluginStateChangedEvent('p1', true);
      final state3 = PluginStateChangedEvent('p1', false);
      expect(state1, equals(state2));
      expect(state1 == state3, isFalse);
    });
  });

  group('PluginRegistry & EventBus Tests', () {
    test('EventBusImpl 错误隔离与背压丢弃机制 (P2-4)', () async {
      final bus = EventBusImpl(maxQueueDepth: 2);
      final received = <AppEvent>[];
      final sub = bus.on<AppEvent>().listen(received.add);

      bus.fire(PluginInstalledEvent('p1'));
      bus.fire(PluginInstalledEvent('p2'));
      // 超限触发背压
      bus.fire(PluginInstalledEvent('p3'));

      await Future.delayed(const Duration(milliseconds: 30));
      expect(received.length, lessThanOrEqualTo(2));

      // 已关闭安全分发不抛异常
      bus.dispose();
      expect(() => bus.fire(PluginInstalledEvent('p4')), returnsNormally);
      await sub.cancel();
    });
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

    test('PluginPermission 支持全新扩展权限解析', () {
      expect(PluginPermission.fromString('screen'), PluginPermission.screen);
      expect(PluginPermission.fromString('location'), PluginPermission.location);
      expect(PluginPermission.fromString('bluetooth'), PluginPermission.bluetooth);
      expect(PluginPermission.fromString('nfc'), PluginPermission.nfc);
      expect(PluginPermission.fromString('ai'), PluginPermission.ai);
      expect(PluginPermission.fromString('database'), PluginPermission.database);
      expect(PluginPermission.fromString('db'), PluginPermission.database);
      expect(PluginPermission.fromString('ipc'), PluginPermission.ipc);
    });

    test('PluginIpcBroker 注册、调用与生命周期隔离', () async {
      final broker = PluginIpcBroker.instance;
      broker.reset();

      // 注册服务
      broker.registerService('math_tool', 'add', (args) async {
        if (args is List && args.length >= 2) {
          return (args[0] as num) + (args[1] as num);
        }
        return 0;
      });

      expect(broker.hasService('math_tool', 'add'), isTrue);
      expect(broker.hasService('math_tool', 'sub'), isFalse);

      // 调用成功
      final res = await broker.call(
        callerPluginId: 'caller',
        targetPluginId: 'math_tool',
        functionName: 'add',
        args: [10, 25],
      );
      expect(res['ok'], isTrue);
      expect(res['result'], 35);

      // 调用未注册服务
      final failRes = await broker.call(
        callerPluginId: 'caller',
        targetPluginId: 'math_tool',
        functionName: 'unknown',
      );
      expect(failRes['ok'], isFalse);
      expect(failRes['error'], contains('未暴露接口'));

      // 注销服务
      broker.unregisterService('math_tool', 'add');
      expect(broker.hasService('math_tool', 'add'), isFalse);
    });
  });
}

