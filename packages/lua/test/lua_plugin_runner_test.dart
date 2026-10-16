import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';
import 'package:plugin_toolbox_lua/plugin_toolbox_lua.dart';

class _SimpleStateDelegate implements LuaStateDelegate {
  final Map<String, dynamic> state = {};

  @override
  void onStateChanged(String key, dynamic value) {
    state[key] = value;
  }

  @override
  dynamic getState(String key) => state[key];

  @override
  Map<String, dynamic> getAllStates() => Map.unmodifiable(state);
}

class _InMemoryStorage implements PluginStorage {
  final Map<String, dynamic> _data = {};

  @override
  Future<String?> getString(String key) async => _data[key] as String?;

  @override
  Future<bool> setString(String key, String value) async {
    _data[key] = value;
    return true;
  }

  @override
  Future<bool?> getBool(String key) async => _data[key] as bool?;

  @override
  Future<bool> setBool(String key, bool value) async {
    _data[key] = value;
    return true;
  }

  @override
  Future<int?> getInt(String key) async => _data[key] as int?;

  @override
  Future<bool> setInt(String key, int value) async {
    _data[key] = value;
    return true;
  }

  @override
  Future<double?> getDouble(String key) async => _data[key] as double?;

  @override
  Future<bool> setDouble(String key, double value) async {
    _data[key] = value;
    return true;
  }

  @override
  Future<List<String>?> getStringList(String key) async =>
      _data[key] as List<String>?;

  @override
  Future<bool> setStringList(String key, List<String> value) async {
    _data[key] = value;
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    _data.remove(key);
    return true;
  }

  @override
  Future<bool> clear() async {
    _data.clear();
    return true;
  }

  @override
  Future<dynamic> getValue(String key) async => _data[key];

  @override
  Future<bool> setValue(String key, dynamic value) async {
    _data[key] = value;
    return true;
  }

  @override
  Future<dynamic> get(String key) => getValue(key);

  @override
  Future<bool> set(String key, dynamic value) => setValue(key, value);

  @override
  Future<bool> flush() async => true;
}

void main() {
  group('LuaPluginRunner Lifecycle & Dispatch', () {
    late Directory tempDir;
    late PluginManifest manifest;
    late _SimpleStateDelegate stateDelegate;
    late CompositeLuaHostDelegate delegate;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('runner_test_');
      manifest = const PluginManifest(
        id: 'test_runner_plugin',
        name: 'Runner Test Plugin',
        version: '1.0.0',
        description: 'Test runner plugin description',
        author: 'Unit Test',
        minAppVersion: '0.1.0',
        type: 'lua',
        category: PluginCategory.other,
        permissions: [],
        entry: 'main.lua',
        ui: 'ui.json',
      );
      stateDelegate = _SimpleStateDelegate();
      delegate = CompositeLuaHostDelegate(stateDelegate: stateDelegate);
    });

    tearDown(() {
      try {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      } catch (_) {}
    });

    test('未完成初始化的插件启动时抛出 StateError', () {
      final uninitializedPlugin = DynamicPlugin(
        manifest: manifest,
        rootDir: tempDir,
      );
      expect(
        () => LuaPluginRunner(
          plugin: uninitializedPlugin,
          delegate: delegate,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('入口脚本不存在时 start() 抛出 FileSystemException', () async {
      final plugin = DynamicPlugin(
        manifest: manifest,
        rootDir: tempDir,
      );
      final ctx = PluginContext(
        pluginId: plugin.id,
        storage: _InMemoryStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {},
      );
      await plugin.initialize(ctx);

      final runner = LuaPluginRunner(plugin: plugin, delegate: delegate);
      expect(runner.start(), throwsA(isA<FileSystemException>()));
      runner.dispose();
    });

    test('正常加载执行 main.lua 并驱动完整生命周期与动作派发', () async {
      final scriptFile = File('${tempDir.path}/main.lua');
      scriptFile.writeAsStringSync('''
        function onInit()
          state.set("status", "initialized")
        end

        function greet(name)
          state.set("greeting", "Hello, " .. name)
        end

        function onResume()
          state.set("lifecycle", "resumed")
        end

        function onPause()
          state.set("lifecycle", "paused")
        end

        function onDispose()
          state.set("lifecycle", "disposed")
        end

        function onDestroy()
          state.set("lifecycle", "destroyed")
        end
      ''');

      final plugin = DynamicPlugin(
        manifest: manifest,
        rootDir: tempDir,
      );
      final ctx = PluginContext(
        pluginId: plugin.id,
        storage: _InMemoryStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {PluginPermission.storage},
      );
      await plugin.initialize(ctx);

      final runner = LuaPluginRunner(plugin: plugin, delegate: delegate);
      expect(runner.engine, isNotNull);

      // 启动并调用 onInit
      await runner.start();
      expect(stateDelegate.getState('status'), equals('initialized'));

      // 派发自定义 Action
      runner.dispatchAction('greet', ['Alice']);
      expect(stateDelegate.getState('greeting'), equals('Hello, Alice'));

      // 驱动生命周期事件
      runner.onResume();
      expect(stateDelegate.getState('lifecycle'), equals('resumed'));

      runner.onPause();
      expect(stateDelegate.getState('lifecycle'), equals('paused'));

      // 销毁并关闭引擎
      runner.dispose();
      expect(stateDelegate.getState('lifecycle'), equals('destroyed'));
    });

    test('生命周期钩子缺失或执行异常时安全降级不崩溃', () async {
      final scriptFile = File('${tempDir.path}/main.lua');
      scriptFile.writeAsStringSync('''
        -- 仅定义 onInit，其他生命周期函数故意不声明
        function onInit()
          state.set("ready", true)
        end
      ''');

      final plugin = DynamicPlugin(
        manifest: manifest,
        rootDir: tempDir,
      );
      final ctx = PluginContext(
        pluginId: plugin.id,
        storage: _InMemoryStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {},
      );
      await plugin.initialize(ctx);

      final runner = LuaPluginRunner(plugin: plugin, delegate: delegate);
      await runner.start();
      expect(stateDelegate.getState('ready'), isTrue);

      // 缺失钩子安全调用
      expect(() => runner.onResume(), returnsNormally);
      expect(() => runner.onPause(), returnsNormally);
      expect(() => runner.dispose(), returnsNormally);
    });
  });
}
