import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';
import 'package:plugin_toolbox_lua/plugin_toolbox_lua.dart';

import 'helpers/lua_test_helpers.dart';

Future<void> _waitFor(
  bool Function() condition, {
  int maxTries = 40,
  int stepMs = 25,
}) =>
    waitForCondition(condition, maxTries: maxTries, stepMs: stepMs);

void main() {
  group('NetworkApi 拓展方法与边界拦截测试', () {
    late PluginContext context;
    late MockLuaHostDelegate delegate;
    late LuaEngine engine;

    setUp(() {
      delegate = MockLuaHostDelegate();
      context = PluginContext(
        pluginId: 'net_ext_test',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {PluginPermission.network},
        allowedDomains: const ['api.example.com'],
      );
      engine = LuaEngine(context: context, delegate: delegate);
    });

    tearDown(() => engine.close());

    test('network.put, delete, request 白名单外域名与非法 URL 拦截', () async {
      // 1. 非法 URL
      expect(
        () => engine.loadAndExecute('network.get(":::not a valid url:::")'),
        throwsException,
      );

      // 2. 白名单外域名
      engine.loadAndExecute('''
        network.put("https://evil.com/data", "{}", function(res)
          state.set("put_err", res.error)
        end)
        network.delete("https://evil.com/data", function(res)
          state.set("del_err", res.error)
        end)
      ''');

      await _waitFor(() =>
          delegate.getState('put_err') != null &&
          delegate.getState('del_err') != null);

      expect(delegate.getState('put_err'), contains('域名不在白名单内'));
      expect(delegate.getState('del_err'), contains('域名不在白名单内'));

      // 3. network.request 参数类型错误
      expect(
        () => engine.loadAndExecute('network.request("not_a_table")'),
        throwsException,
      );

      // 4. network.request 白名单拦截
      engine.loadAndExecute('''
        network.request({ url = "https://untrusted.org/api", method = "POST" }, function(res)
          state.set("req_err", res.error)
        end)
      ''');
      await _waitFor(() => delegate.getState('req_err') != null);
      expect(delegate.getState('req_err'), contains('域名不在白名单内'));
    });

    test('network.resolveDns 白名单与越界拦截', () async {
      engine.loadAndExecute('''
        network.resolveDns("evil.com", function(res)
          state.set("dns_res_ok", res.ok)
          state.set("dns_res_err", res.error)
        end)
      ''');

      await _waitFor(() => delegate.getState('dns_res_ok') != null);
      expect(delegate.getState('dns_res_ok'), isFalse);
      expect(delegate.getState('dns_res_err'), contains('域名不在白名单内'));
    });

    test('network.ping 白名单与 SSRF 本地私网拦截', () async {
      engine.loadAndExecute('''
        network.ping("disallowed.com", function(res)
          state.set("ping_disallowed_ok", res.reachable)
          state.set("ping_disallowed_err", res.error)
        end)
        network.ping("127.0.0.1", function(res)
          state.set("ping_ssrf_ok", res.reachable)
          state.set("ping_ssrf_err", res.error)
        end)
      ''');

      await _waitFor(() =>
          delegate.getState('ping_disallowed_ok') != null &&
          delegate.getState('ping_ssrf_ok') != null);

      expect(delegate.getState('ping_disallowed_ok'), isFalse);
      expect(delegate.getState('ping_disallowed_err'), contains('域名不在白名单内'));
      expect(delegate.getState('ping_ssrf_ok'), isFalse);
    });

    test('network.getWifiInfo 委托宿主获取无线网络信息', () async {
      engine.loadAndExecute('''
        network.getWifiInfo(function(info)
          state.set("wifi_ssid", info.ssid)
          state.set("wifi_ip", info.ip)
        end)
      ''');

      await _waitFor(() =>
          delegate.getState('wifi_ssid') != null &&
          delegate.getState('wifi_ip') != null);

      expect(delegate.getState('wifi_ssid'), 'Toolbox-WiFi');
      expect(delegate.getState('wifi_ip'), '192.168.1.100');
    });

    test('network.scanPort 白名单与私网防护', () async {
      engine.loadAndExecute('''
        network.scanPort("untrusted-scan.com", 80, function(res)
          state.set("scan_disallowed", res.error)
        end)
        network.scanPort("192.168.1.1", 80, function(res)
          state.set("scan_ssrf", res.error)
        end)
      ''');

      await _waitFor(() =>
          delegate.getState('scan_disallowed') != null &&
          delegate.getState('scan_ssrf') != null);

      expect(delegate.getState('scan_disallowed'), contains('不在白名单内'));
      expect(delegate.getState('scan_ssrf'), contains('不在白名单内'));
    });
  });
}
