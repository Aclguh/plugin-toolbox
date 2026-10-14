import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

    test('PluginManifest 支持 allowedDomains 域名白名单解析与序列化', () {
      final json = {
        'id': 'net_plugin',
        'name': 'Net Plugin',
        'allowedDomains': ['api.example.com', '*.github.com', 'MY-API.ORG'],
      };
      final manifest = PluginManifest.fromJson(json);
      expect(manifest.allowedDomains, [
        'api.example.com',
        '*.github.com',
        'my-api.org',
      ]);
      expect(manifest.toJson()['allowedDomains'], [
        'api.example.com',
        '*.github.com',
        'my-api.org',
      ]);
    });

    test('PluginContext.isHostAllowed 支持精确匹配、通配符与端口兼容', () {
      final ctx = PluginContext(
        pluginId: 'csp_test',
        storage: PluginStorageImpl(namespace: 'csp_test'),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {PluginPermission.network},
        allowedDomains: ['api.example.com', '*.github.com', 'internal.lan'],
      );

      // 精确匹配与大小写不敏感
      expect(ctx.isHostAllowed('api.example.com'), isTrue);
      expect(ctx.isHostAllowed('API.EXAMPLE.COM'), isTrue);

      // 携带端口
      expect(ctx.isHostAllowed('api.example.com:443'), isTrue);
      expect(ctx.isHostAllowed('internal.lan:8080'), isTrue);

      // 通配符与子域匹配
      expect(ctx.isHostAllowed('github.com'), isTrue);
      expect(ctx.isHostAllowed('raw.github.com'), isTrue);
      expect(ctx.isHostAllowed('sub.raw.github.com'), isTrue);

      // 未授权域名与内网 IP 拦截
      expect(ctx.isHostAllowed('evil.com'), isFalse);
      expect(ctx.isHostAllowed('notgithub.com'), isFalse);
      expect(ctx.isHostAllowed('192.168.1.1'), isFalse);
      expect(ctx.isHostAllowed('127.0.0.1:8000'), isFalse);

      // 无白名单限制时默认全量放行
      final unconfinedCtx = PluginContext(
        pluginId: 'unconfined',
        storage: PluginStorageImpl(namespace: 'unconfined'),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {PluginPermission.network},
      );
      expect(unconfinedCtx.isHostAllowed('any-domain.com'), isTrue);
      expect(unconfinedCtx.isHostAllowed('192.168.1.1'), isTrue);
    });

    test('AppEvent 具有正确的 Equatable 值对象等价语义 (P3-1)', () {
      final now = DateTime.now();
      final event1 = PluginInstalledEvent('p1', timestamp: now);
      final event2 = PluginInstalledEvent('p1',
          timestamp: now.add(const Duration(seconds: 1)));
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

    test('same-id re-register re-initializes the new instance (插件更新场景)',
        () async {
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
      expect(
          PluginPermission.fromString('location'), PluginPermission.location);
      expect(
          PluginPermission.fromString('bluetooth'), PluginPermission.bluetooth);
      expect(PluginPermission.fromString('nfc'), PluginPermission.nfc);
      expect(PluginPermission.fromString('ai'), PluginPermission.ai);
      expect(
          PluginPermission.fromString('database'), PluginPermission.database);
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

    test('PluginIpcBroker 支持独立实例化与依赖注入隔离', () async {
      final customBroker = PluginIpcBroker();
      customBroker.registerService(
          'service_a', 'echo', (arg) async => 'echo:$arg');
      expect(customBroker.hasService('service_a', 'echo'), isTrue);
      expect(PluginIpcBroker.instance.hasService('service_a', 'echo'), isFalse);

      final res = await customBroker.call(
        callerPluginId: 'c',
        targetPluginId: 'service_a',
        functionName: 'echo',
        args: 'hello',
      );
      expect(res['ok'], isTrue);
      expect(res['result'], 'echo:hello');
    });

    test('PluginIpcBroker 细粒度权限控制与调用方白名单 (ACL)', () async {
      final broker = PluginIpcBroker();
      // 仅允许 'trusted_plugin' 调用的敏感接口
      broker.registerService(
        'secure_vault',
        'getSecret',
        (arg) async => 'top_secret',
        allowedCallers: {'trusted_plugin'},
      );

      // 白名单内的合法插件调用成功
      final okRes = await broker.call(
        callerPluginId: 'trusted_plugin',
        targetPluginId: 'secure_vault',
        functionName: 'getSecret',
      );
      expect(okRes['ok'], isTrue);
      expect(okRes['result'], 'top_secret');

      // 未授权插件调用被拦截拒绝
      final deniedRes = await broker.call(
        callerPluginId: 'unauthorized_plugin',
        targetPluginId: 'secure_vault',
        functionName: 'getSecret',
      );
      expect(deniedRes['ok'], isFalse);
      expect(deniedRes['error'], contains('跨插件访问拒绝'));

      // 公开接口任何插件均可调用
      broker.registerService(
        'public_service',
        'ping',
        (arg) async => 'pong',
      );
      final pingRes = await broker.call(
        callerPluginId: 'any_caller',
        targetPluginId: 'public_service',
        functionName: 'ping',
      );
      expect(pingRes['ok'], isTrue);
      expect(pingRes['result'], 'pong');
    });

    test('PluginIpcBroker 跨插件调用超时熔断', () async {
      final broker = PluginIpcBroker();
      broker.registerService('slow_service', 'hang', (arg) async {
        await Future.delayed(const Duration(milliseconds: 100));
        return 'delayed_result';
      });

      // 显式指定 20ms 超时，触发熔断
      final timeoutRes = await broker.call(
        callerPluginId: 'caller',
        targetPluginId: 'slow_service',
        functionName: 'hang',
        timeout: const Duration(milliseconds: 20),
      );

      expect(timeoutRes['ok'], isFalse);
      expect(timeoutRes['code'], 'IPC_TIMEOUT');
      expect(timeoutRes['error'], contains('超时'));
    });

    test('PluginIpcBroker 跨插件调用频次限流保护', () async {
      final broker = PluginIpcBroker();
      broker.registerService('fast_service', 'ping', (arg) async => 'pong');

      // 限制每秒最多 3 次调用
      for (var i = 0; i < 3; i++) {
        final res = await broker.call(
          callerPluginId: 'caller',
          targetPluginId: 'fast_service',
          functionName: 'ping',
          maxCallsPerSecond: 3,
        );
        expect(res['ok'], isTrue);
      }

      // 第 4 次调用触发限流
      final blockedRes = await broker.call(
        callerPluginId: 'caller',
        targetPluginId: 'fast_service',
        functionName: 'ping',
        maxCallsPerSecond: 3,
      );
      expect(blockedRes['ok'], isFalse);
      expect(blockedRes['code'], 'IPC_RATE_LIMITED');
      expect(blockedRes['error'], contains('调用频次超限'));
    });

    test('PluginRegistry 停用插件与自定义权限状态机及注销清理', () async {
      final reg = PluginRegistry(
        storageFactory: const PluginStorageFactory(),
        eventBus: EventBusImpl(),
        logger: Logger(),
      );
      const manifest = PluginManifest(
        id: 'p_test',
        name: 'P Test',
        version: '1.0.0',
        description: 'd',
        author: 'a',
        type: 'lua',
        category: PluginCategory.other,
        permissions: [PluginPermission.camera, PluginPermission.storage],
        entry: 'main.lua',
        ui: 'ui.json',
      );
      final plugin = DynamicPlugin(manifest: manifest, rootDir: Directory('.'));
      reg.register(plugin);

      // 加载停用集合与自定义权限覆盖
      reg.loadDisabledPlugins({'p_test'});
      expect(reg.disabledPluginIds, contains('p_test'));

      reg.loadCustomPermissions({
        'p_test': {PluginPermission.storage},
      });
      expect(reg.getCustomPermissions('p_test'), {PluginPermission.storage});

      // 重新启用
      await reg.setEnabled('p_test', true);
      expect(reg.disabledPluginIds.contains('p_test'), isFalse);

      // 验证升级场景下非敏感权限自动合并
      const manifestV2 = PluginManifest(
        id: 'p_test',
        name: 'P Test',
        version: '1.1.0',
        description: 'd',
        author: 'a',
        type: 'lua',
        category: PluginCategory.other,
        permissions: [PluginPermission.storage, PluginPermission.clipboard],
        entry: 'main.lua',
        ui: 'ui.json',
      );
      final pluginV2 =
          DynamicPlugin(manifest: manifestV2, rootDir: Directory('.'));
      reg.register(pluginV2);
      await reg.initializePlugin('p_test');
      expect(
        reg.getCustomPermissions('p_test'),
        containsAll([PluginPermission.storage, PluginPermission.clipboard]),
      );

      // 注销后清理相关映射
      await reg.unregister('p_test');
      expect(reg.getCustomPermissions('p_test'), isNull);
      expect(reg.disabledPluginIds.contains('p_test'), isFalse);
    });

    test('TypeConverter 支持数值、布尔与多格式十六进制颜色安全转换', () {
      expect(TypeConverter.tryDouble('12.34'), 12.34);
      expect(TypeConverter.tryDouble(56), 56.0);
      expect(TypeConverter.tryDouble('invalid'), isNull);
      expect(TypeConverter.tryDouble(null), isNull);

      expect(TypeConverter.tryInt('42'), 42);
      expect(TypeConverter.tryInt(100.9), 100);
      expect(TypeConverter.tryInt(null), isNull);

      expect(TypeConverter.tryBool('true'), isTrue);
      expect(TypeConverter.tryBool('false'), isFalse);
      expect(TypeConverter.tryBool(1), isTrue);
      expect(TypeConverter.tryBool(0), isFalse);
      expect(TypeConverter.tryBool(null, fallback: true), isTrue);

      expect(TypeConverter.parseColorHex('#F00'), 0xFFFF0000);
      expect(TypeConverter.parseColorHex('#26366A'), 0xFF26366A);
      expect(TypeConverter.parseColorHex('26366A'), 0xFF26366A);
      expect(TypeConverter.parseColorHex('#8026366A'), 0x8026366A);
      expect(TypeConverter.parseColorHex('#XYZ123'), isNull);
      expect(TypeConverter.parseColorHex(''), isNull);
      expect(TypeConverter.parseColorHex(null), isNull);
    });
  });

  group('PluginFileStorage Tests', () {
    late Directory tempDir;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      tempDir = Directory.systemTemp.createTempSync('ptx_storage_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('PluginStorageFactory 根据是否提供 rootDir 返回对应实现', () {
      const factory = PluginStorageFactory();
      final defaultStorage = factory.create('p1');
      expect(defaultStorage, isA<PluginStorageImpl>());

      final fileStorage = factory.create('p2', rootDir: tempDir);
      expect(fileStorage, isA<PluginFileStorageImpl>());
    });

    test('PluginFileStorageImpl 支持多种数据类型读写与持久化至 storage.json', () async {
      final storage =
          PluginFileStorageImpl(namespace: 'test_ns', rootDir: tempDir);
      final storageFile = File('${tempDir.path}/storage.json');

      expect(await storage.getString('k_str'), isNull);
      expect(await storage.setString('k_str', 'hello'), isTrue);
      expect(await storage.getString('k_str'), 'hello');

      expect(await storage.setBool('k_bool', true), isTrue);
      expect(await storage.getBool('k_bool'), isTrue);

      expect(await storage.setInt('k_int', 42), isTrue);
      expect(await storage.getInt('k_int'), 42);

      expect(await storage.setDouble('k_double', 3.14), isTrue);
      expect(await storage.getDouble('k_double'), 3.14);

      expect(await storage.setStringList('k_list', ['a', 'b']), isTrue);
      expect(await storage.getStringList('k_list'), ['a', 'b']);

      expect(storageFile.existsSync(), isTrue);

      // 验证跨实例重新从磁盘加载
      final storage2 =
          PluginFileStorageImpl(namespace: 'test_ns', rootDir: tempDir);
      expect(await storage2.getString('k_str'), 'hello');
      expect(await storage2.getInt('k_int'), 42);

      // 单项删除
      expect(await storage.remove('k_str'), isTrue);
      expect(await storage.getString('k_str'), isNull);

      // 清空
      expect(await storage.clear(), isTrue);
      expect(await storage.getInt('k_int'), isNull);
      expect(storageFile.existsSync(), isFalse);
    });

    test('PluginFileStorageImpl 支持平滑迁移旧版 SharedPreferences 遗留数据', () async {
      SharedPreferences.setMockInitialValues({
        'plugin.mig_ns.legacy_text': 'migrated_val',
        'plugin.other_ns.unrelated': 'should_ignore',
      });

      final storage =
          PluginFileStorageImpl(namespace: 'mig_ns', rootDir: tempDir);
      expect(await storage.getString('legacy_text'), 'migrated_val');
      expect(await storage.getString('unrelated'), isNull);

      // 验证已落盘至 storage.json
      final storageFile = File('${tempDir.path}/storage.json');
      expect(storageFile.existsSync(), isTrue);
      expect(storageFile.readAsStringSync(), contains('migrated_val'));
    });

    test('PluginFileStorageImpl 并发写入串行排队保证数据不丢失无竞态异常', () async {
      final storage =
          PluginFileStorageImpl(namespace: 'concurrent_ns', rootDir: tempDir);
      final futures = <Future<bool>>[];
      for (int i = 0; i < 30; i++) {
        futures.add(storage.setString('key_$i', 'val_$i'));
      }
      final results = await Future.wait(futures);
      expect(results.every((r) => r == true), isTrue);

      final storageReloaded =
          PluginFileStorageImpl(namespace: 'concurrent_ns', rootDir: tempDir);
      for (int i = 0; i < 30; i++) {
        expect(await storageReloaded.getString('key_$i'), 'val_$i');
      }
    });

    test('PluginFileStorageImpl 主文件损坏时自动从 .bak 备份恢复数据', () async {
      final storage =
          PluginFileStorageImpl(namespace: 'backup_ns', rootDir: tempDir);
      await storage.setString('safe_key', 'safe_value');

      final mainFile = File('${tempDir.path}/storage.json');
      final bakFile = File('${tempDir.path}/storage.json.bak');
      // 触发第二次写入以生成 .bak 备份
      await storage.setString('safe_key_2', 'safe_value_2');
      expect(bakFile.existsSync(), isTrue);

      // 人为破坏主文件为乱码
      await mainFile.writeAsString('<<<invalid_corrupted_json>>>', flush: true);

      // 新建实例读取，应能自动从 .bak 恢复健康数据
      final recoveryStorage =
          PluginFileStorageImpl(namespace: 'backup_ns', rootDir: tempDir);
      expect(await recoveryStorage.getString('safe_key'), 'safe_value');
    });
  });
}
