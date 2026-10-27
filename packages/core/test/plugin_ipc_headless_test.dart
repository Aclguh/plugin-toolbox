import 'package:test/test.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';

void main() {
  late PluginIpcBroker broker;

  setUp(() {
    broker = PluginIpcBroker();
  });

  tearDown(() {
    broker.reset();
  });

  test('PluginIpcBroker 无头拉起器按需唤醒目标插件并完成服务调用', () async {
    final launchedPlugins = <String>[];

    // 配置无头按需唤醒钩子
    broker.headlessLauncher = (targetPluginId) async {
      launchedPlugins.add(targetPluginId);
      if (targetPluginId == 'weather_service') {
        // 模拟后台拉起后注册服务
        broker.registerService(
          'weather_service',
          'getTemperature',
          (args) async => {'city': args?['city'], 'temp': 24.5},
        );
        return true;
      }
      return false;
    };

    // 初始状态下服务不存在
    expect(broker.hasService('weather_service', 'getTemperature'), isFalse);

    // 发起跨插件调用
    final res = await broker.call(
      callerPluginId: 'dashboard_plugin',
      targetPluginId: 'weather_service',
      functionName: 'getTemperature',
      args: {'city': 'Hangzhou'},
    );

    expect(launchedPlugins, ['weather_service']);
    expect(res['ok'], isTrue);
    expect(res['result'], {'city': 'Hangzhou', 'temp': 24.5});
  });

  test('PluginIpcBroker 无头拉起器返回 false 时降级返回未暴露接口错误', () async {
    broker.headlessLauncher = (targetPluginId) async => false;

    final res = await broker.call(
      callerPluginId: 'app_main',
      targetPluginId: 'unknown_plugin',
      functionName: 'ping',
    );

    expect(res['ok'], isFalse);
    expect(res['error'], contains('未暴露接口'));
  });

  test('PluginIpcBroker 无头拉起器抛出异常时返回 HEADLESS_WAKEUP_FAILED 错误码', () async {
    broker.headlessLauncher = (targetPluginId) async {
      throw StateError('沙箱目录损坏或脚本语法错误');
    };

    final res = await broker.call(
      callerPluginId: 'app_main',
      targetPluginId: 'corrupted_plugin',
      functionName: 'init',
    );

    expect(res['ok'], isFalse);
    expect(res['code'], 'HEADLESS_WAKEUP_FAILED');
    expect(res['error'], contains('唤醒失败'));
  });
}
