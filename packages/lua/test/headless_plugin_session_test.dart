import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';
import 'package:plugin_toolbox_lua/plugin_toolbox_lua.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late DynamicPlugin mockServicePlugin;
  late HeadlessPluginSessionManager sessionManager;

  setUp(() async {
    PluginIpcBroker.instance.reset();

    tempDir = await Directory.systemTemp.createTemp('headless_test_');

    const manifest = PluginManifest(
      id: 'math_service',
      name: '后台计算服务',
      version: '1.0.0',
      description: '提供数学计算与转换的无头后台插件',
      author: 'Tester',
      type: 'lua',
      category: PluginCategory.calculator,
      entry: 'main.lua',
      ui: 'ui/main.ui.json',
      permissions: [PluginPermission.ipc, PluginPermission.storage],
    );

    mockServicePlugin = DynamicPlugin(
      manifest: manifest,
      rootDir: tempDir,
    );

    final context = PluginContext(
      pluginId: 'math_service',
      storage: const PluginStorageFactory().create(
        'math_service',
        rootDir: tempDir,
      ),
      eventBus: EventBusImpl(),
      logger: Logger(),
      grantedPermissions: {PluginPermission.ipc, PluginPermission.storage},
      rootDir: tempDir,
    );

    final mainFile = File('${tempDir.path}/main.lua');
    await mainFile.create(recursive: true);
    await mainFile.writeAsString('''
      local wasHeadless = plugin.isHeadless()
      state.set('was_headless', wasHeadless)

      -- 导出后台服务
      plugin.export('square', function(args)
        local val = args and args.num or 0
        return { result = val * val }
      end)

      function onInit()
        state.set('init_done', true)
      end
    ''');

    await mockServicePlugin.initialize(context);
    sessionManager = HeadlessPluginSessionManager(
      defaultIdleTimeout: const Duration(seconds: 10),
    );
  });

  tearDown(() async {
    sessionManager.closeAll();
    PluginIpcBroker.instance.reset();
    try {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  test('HeadlessPluginSession 启动无头会话并在 Lua 中正确识别 isHeadless 标记', () async {
    final session = HeadlessPluginSession(plugin: mockServicePlugin);
    await session.start();

    expect(session.delegate.isHeadless, isTrue);
    expect(session.delegate.getState('was_headless'), isTrue);
    expect(session.delegate.getState('init_done'), isTrue);

    // 验证服务已被自动注册至全局 IPC Broker
    expect(
        PluginIpcBroker.instance.hasService('math_service', 'square'), isTrue);

    session.dispose();
    expect(session.isDisposed, isTrue);
    expect(
        PluginIpcBroker.instance.hasService('math_service', 'square'), isFalse);
  });

  test('PluginIpcBroker 跨插件调用按需拉起无头会话并完成数据交互', () async {
    // 将无头管理器接入 Broker
    PluginIpcBroker.instance.headlessLauncher = (targetPluginId) async {
      if (targetPluginId == mockServicePlugin.id) {
        await sessionManager.getOrLaunch(mockServicePlugin);
        return true;
      }
      return false;
    };

    expect(sessionManager.isSessionActive('math_service'), isFalse);
    expect(
        PluginIpcBroker.instance.hasService('math_service', 'square'), isFalse);

    // 前台插件发起调用，触发无头按需唤醒
    final res = await PluginIpcBroker.instance.call(
      callerPluginId: 'frontend_caller',
      targetPluginId: 'math_service',
      functionName: 'square',
      args: {'num': 9},
    );

    expect(res['ok'], isTrue);
    expect(res['result'], {'result': 81});
    expect(sessionManager.isSessionActive('math_service'), isTrue);

    // 再次调用，复用已有活跃会话
    final res2 = await PluginIpcBroker.instance.call(
      callerPluginId: 'frontend_caller',
      targetPluginId: 'math_service',
      functionName: 'square',
      args: {'num': 12},
    );
    expect(res2['ok'], isTrue);
    expect(res2['result'], {'result': 144});
  });

  test('HeadlessPluginSessionManager 手动关闭与全局清理', () async {
    final session = await sessionManager.getOrLaunch(mockServicePlugin);
    expect(sessionManager.isSessionActive(mockServicePlugin.id), isTrue);

    sessionManager.closeSession(mockServicePlugin.id);
    expect(sessionManager.isSessionActive(mockServicePlugin.id), isFalse);
    expect(session.isDisposed, isTrue);
  });
}
