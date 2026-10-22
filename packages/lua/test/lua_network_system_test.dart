import 'dart:io';
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
  group('Lua Network & System APIs', () {
    late MockLuaHostDelegate delegate;
    late PluginContext context;
    late LuaEngine engine;

    setUp(() {
      delegate = MockLuaHostDelegate();
      context = PluginContext(
        pluginId: 'test_plugin',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {
          PluginPermission.clipboard,
          PluginPermission.storage,
        },
      );
      engine = LuaEngine(context: context, delegate: delegate);
    });

    tearDown(() {
      engine.close();
    });

    test('未声明 network 权限时 network.post 直接报错', () {
      expect(
        () => engine.loadAndExecute('network.post("http://example.com", "{}")'),
        throwsException,
      );
    });

    test('network.post 以绑定形式注入 (仅验证绑定)', () {
      engine.loadAndExecute('state.set("post_fn", type(network.post))');
      expect(delegate.getState('post_fn'), 'function');
    });

    test('UiApi 软键盘收起与 Toast 委派给宿主', () {
      engine.loadAndExecute('''
        ui.hideKeyboard()
        ui.toast("测试提示")
      ''');
      expect(delegate.keyboardHidden, true);
      expect(delegate.toasts.contains('测试提示'), true);
    });

    test('ShareApi 文本分享委派给宿主', () {
      engine.loadAndExecute('share.text("分享文本内容", "主题")');
      expect(delegate.sharedText, '分享文本内容');
    });

    test('ShareApi 文件分享防路径穿越并委派宿主', () async {
      final tempDir = Directory.systemTemp.createTempSync('ptx_share_test_');
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });
      final testFile = File('${tempDir.path}/report.csv')
        ..writeAsStringSync('a,b,c');

      final shareCtx = PluginContext(
        pluginId: 'share_test',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {PluginPermission.storage},
        rootDir: tempDir,
      );
      final shareEngine = LuaEngine(context: shareCtx, delegate: delegate);

      // 1. 越界分享拦截
      expect(
        () => shareEngine.loadAndExecute('share.file("../secret.txt")'),
        throwsException,
      );

      // 2. 正常合法文件分享
      shareEngine.loadAndExecute('''
        share.file("report.csv", "text/csv", "分享报表", function(ok)
          state.set("share_ok", ok)
        end)
      ''');

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(delegate.sharedFilePath, testFile.path);
      expect(delegate.sharedFileMimeType, 'text/csv');
      expect(delegate.sharedFileSubject, '分享报表');
      expect(delegate.getState('share_ok'), true);
    });

    test('SystemApi.openUrl 外部链接跳转委派给宿主', () {
      engine.loadAndExecute('system.openUrl("https://example.com")');
      expect(delegate.openedUrl, 'https://example.com');
    });

    test('TimerApi setTimeout 与 clear', () async {
      engine.loadAndExecute('''
        timer.setTimeout(10, function()
          state.set("timeout_called", true)
        end)
        local toCancel = timer.setTimeout(500, function()
          state.set("cancelled_called", true)
        end)
        timer.clear(toCancel)
      ''');

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(delegate.getState('timeout_called'), true);
      expect(delegate.getState('cancelled_called'), isNull);
    });

    test('TimerApi clearAll 与 close 自动回收所有定时器', () async {
      engine.loadAndExecute('''
        timer.setTimeout(200, function()
          state.set("never_call", true)
        end)
      ''');
      engine.close();
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(delegate.getState('never_call'), isNull);
    });

    test('NetworkApi 支持 put, delete 与 request 方法绑定', () {
      engine.loadAndExecute('''
        state.set("has_put", type(network.put))
        state.set("has_delete", type(network.delete))
        state.set("has_request", type(network.request))
      ''');

      expect(delegate.getState('has_put'), 'function');
      expect(delegate.getState('has_delete'), 'function');
      expect(delegate.getState('has_request'), 'function');
    });

    test('NotificationApi: 权限控制与通知调度流转', () async {
      // 1. 未声明 notification 权限时报错
      expect(
        () => engine.loadAndExecute('notification.show("测试", "内容")'),
        throwsA(isA<Exception>()),
      );

      // 2. 声明 notification 权限
      final notifCtx = PluginContext(
        pluginId: 'notif_test',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {PluginPermission.notification},
      );
      final notifEngine = LuaEngine(context: notifCtx, delegate: delegate);

      // 3. 即时通知
      notifEngine.loadAndExecute('''
        notification.show("即时提醒", "喝水时间到了", function(id)
          state.set("shown_id", id)
        end)
      ''');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(delegate.sentNotifications.length, 1);
      expect(delegate.sentNotifications.first['title'], '即时提醒');
      expect(delegate.getState('shown_id'), isNotNull);

      // 4. 定时调度通知
      notifEngine.loadAndExecute('''
        notification.schedule("番茄钟", "专注结束", 1500, function(id)
          state.set("sched_id", id)
        end)
      ''');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(delegate.sentNotifications.length, 2);
      expect(delegate.sentNotifications.last['delaySeconds'], 1500);

      // 5. 取消指定通知与全部取消
      notifEngine.loadAndExecute('''
        notification.cancel(101)
        notification.cancelAll()
      ''');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(delegate.cancelledNotificationIds.contains(101), isTrue);
      expect(delegate.cancelledAllNotifs, isTrue);
    });

    test('DialogApi: prompt 与 pickItem 高级弹窗交互', () async {
      engine.loadAndExecute('''
        dialog.prompt("输入密码", "请输入8位字符", function(text)
          state.set("pwd_input", text)
        end)

        dialog.pickItem("选择进制", {"二进制", "八进制", "十六进制"}, 1, function(item, idx)
          state.set("picked_item", item)
          state.set("picked_idx", idx)
        end)

        dialog.bottomSheet("快捷菜单", {"选项A", "选项B"}, function(item, idx)
          state.set("sheet_item", item)
          state.set("sheet_idx", idx)
        end)
      ''');

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(delegate.getState('pwd_input'), 'user-inputted-text');
      expect(delegate.getState('picked_item'), 'Option 2');
      expect(delegate.getState('picked_idx'), 2);
      expect(delegate.getState('sheet_item'), 'Item 1');
      expect(delegate.getState('sheet_idx'), 1);
    });

    test('SystemApi: 电池电量与网络感知', () async {
      // 1. 同步读取
      engine.loadAndExecute('''
        state.set("batt_sync", system.batteryLevel())
        state.set("charge_sync", system.isCharging())
        state.set("net_sync", system.networkType())
      ''');
      expect(delegate.getState('batt_sync'), 85);
      expect(delegate.getState('charge_sync'), isTrue);
      expect(delegate.getState('net_sync'), 'wifi');

      // 2. 异步回调读取
      engine.loadAndExecute('''
        system.batteryLevel(function(lvl)
          state.set("batt_async", lvl)
        end)
        system.isCharging(function(chg)
          state.set("charge_async", chg)
        end)
        system.networkType(function(net)
          state.set("net_async", net)
        end)
      ''');
      await _waitFor(() =>
          delegate.getState('batt_async') != null &&
          delegate.getState('charge_async') != null &&
          delegate.getState('net_async') != null);
      expect(delegate.getState('batt_async'), 85);
      expect(delegate.getState('charge_async'), isTrue);
      expect(delegate.getState('net_async'), 'wifi');
    });

    test('SocketApi: 权限控制与 TCP/UDP 套接字接口', () async {
      // 1. 无 network 权限时被拒绝
      final noNetCtx = PluginContext(
        pluginId: 'no_net',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {},
      );
      final noNetEngine = LuaEngine(context: noNetCtx, delegate: delegate);
      expect(
        () => noNetEngine
            .loadAndExecute('socket.tcpConnect("127.0.0.1", 8080, {})'),
        throwsException,
      );
      expect(
        () => noNetEngine.loadAndExecute('socket.udpBind(8080, {})'),
        throwsException,
      );

      // 2. 有 network 权限且白名单放行测试主机时正常调用
      final netCtx = PluginContext(
        pluginId: 'net_test',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {PluginPermission.network},
        allowedDomains: ['127.0.0.1'],
      );
      final netEngine = LuaEngine(context: netCtx, delegate: delegate);

      netEngine.loadAndExecute('''
        local id = socket.tcpConnect("127.0.0.1", 9999, {
          onConnect = function(sId) state.set("tcp_conn", sId) end,
          onError = function(sId, err) state.set("tcp_err", err) end,
        })
        state.set("tcp_id", id)

        local okSend = socket.tcpSend(id, "ping")
        state.set("tcp_send_ok", okSend)

        local okClose = socket.tcpClose(id)
        state.set("tcp_close_ok", okClose)

        local udpId = socket.udpBind(0, {
          onData = function(uId, data, addr, port) state.set("udp_data", data) end,
        })
        state.set("udp_id", udpId)
        local okUdpSend = socket.udpSend(udpId, "127.0.0.1", 9999, "hello")
        state.set("udp_send_ok", okUdpSend)
        local okUdpClose = socket.udpClose(udpId)
        state.set("udp_close_ok", okUdpClose)
      ''');

      expect(delegate.getState('tcp_id'), startsWith('tcp_'));
      expect(delegate.getState('udp_id'), startsWith('udp_'));
      expect(delegate.getState('tcp_close_ok'), isTrue);
      expect(delegate.getState('udp_close_ok'), isTrue);

      netEngine.close();
    });

    test('WebSocketApi: 权限控制与接口绑定', () async {
      // 1. 无 network 权限拒绝
      final noNetCtx = PluginContext(
        pluginId: 'no_net',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {},
      );
      final noNetEngine = LuaEngine(context: noNetCtx, delegate: delegate);
      expect(
        () => noNetEngine
            .loadAndExecute('websocket.connect("ws://127.0.0.1:8080", {})'),
        throwsException,
      );

      // 2. 有 network 权限且白名单放行测试主机
      final netCtx = PluginContext(
        pluginId: 'net_test',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {PluginPermission.network},
        allowedDomains: ['127.0.0.1'],
      );
      final netEngine = LuaEngine(context: netCtx, delegate: delegate);

      netEngine.loadAndExecute('''
        local wsId = websocket.connect("ws://127.0.0.1:9999", {
          onOpen = function(id) state.set("ws_open", id) end,
          onError = function(id, err) state.set("ws_err", err) end,
        })
        state.set("ws_id", wsId)
        local sent = websocket.send(wsId, "test")
        state.set("ws_sent", sent)
        local closed = websocket.close(wsId)
        state.set("ws_closed", closed)
      ''');

      expect(delegate.getState('ws_id'), startsWith('ws_'));
      expect(delegate.getState('ws_sent'), isFalse); // 未连上未入表
      expect(delegate.getState('ws_closed'), isTrue);

      netEngine.close();
    });

    test('NetworkApi: resolveDns, ping 与 scanPort 诊断绑定', () async {
      final netCtx = PluginContext(
        pluginId: 'net_test',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {PluginPermission.network},
      );
      final netEngine = LuaEngine(context: netCtx, delegate: delegate);

      netEngine.loadAndExecute('''
        network.resolveDns("127.0.0.1", function(res)
          state.set("dns_ok", res.ok)
          state.set("dns_ips", res.addresses[1])
        end)

        network.ping("127.0.0.1", { port = 80, timeoutMs = 100 }, function(res)
          state.set("ping_done", true)
          state.set("ping_host", res.host)
        end)

        network.scanPort("127.0.0.1", 65534, 100, function(res)
          state.set("scan_done", true)
          state.set("scan_open", res.open)
        end)

        network.getWifiInfo(function(info)
          state.set("wifi_done", true)
          state.set("wifi_ssid", info.ssid)
          state.set("wifi_ip", info.ip)
        end)
      ''');

      await _waitFor(() =>
          delegate.getState('dns_ok') != null &&
          delegate.getState('ping_done') != null &&
          delegate.getState('scan_done') != null &&
          delegate.getState('wifi_done') != null);
      expect(delegate.getState('dns_ok'), isTrue);
      expect(delegate.getState('dns_ips'), '127.0.0.1');
      expect(delegate.getState('ping_done'), isTrue);
      expect(delegate.getState('ping_host'), '127.0.0.1');
      expect(delegate.getState('scan_done'), isTrue);
      expect(delegate.getState('scan_open'), isFalse);
      expect(delegate.getState('wifi_ssid'), 'Toolbox-WiFi');
      expect(delegate.getState('wifi_ip'), '192.168.1.100');

      netEngine.close();
    });

    test('NetworkApi & SocketApi: 域名白名单机制 (CSP) 拦截未授权域名访问', () async {
      final cspCtx = PluginContext(
        pluginId: 'csp_net_test',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {PluginPermission.network},
        allowedDomains: ['api.github.com'],
      );
      final cspEngine = LuaEngine(context: cspCtx, delegate: delegate);

      // 1. 未授权域名的 GET 请求被拦截
      cspEngine.loadAndExecute('''
        network.get("https://evil.com/api", function(res)
          state.set("get_blocked_ok", res.ok)
          state.set("get_blocked_err", res.error)
        end)
      ''');

      // 2. 未授权主机的 resolveDns 被拦截
      cspEngine.loadAndExecute('''
        network.resolveDns("192.168.1.1", function(res)
          state.set("dns_blocked_ok", res.ok)
          state.set("dns_blocked_err", res.error)
        end)
      ''');

      // 3. 未授权主机的 TCP 连接被拦截
      cspEngine.loadAndExecute('''
        socket.tcpConnect("192.168.1.100", 8080, {
          onError = function(id, err)
            state.set("tcp_blocked_err", err)
          end
        })
      ''');

      await _waitFor(() =>
          delegate.getState('get_blocked_ok') != null &&
          delegate.getState('dns_blocked_ok') != null &&
          delegate.getState('tcp_blocked_err') != null);
      expect(delegate.getState('get_blocked_ok'), isFalse);
      expect(
          delegate.getState('get_blocked_err'), contains('域名不在白名单内: evil.com'));
      expect(delegate.getState('dns_blocked_ok'), isFalse);
      expect(delegate.getState('dns_blocked_err'), contains('域名不在白名单内'));
      expect(delegate.getState('tcp_blocked_err'), contains('域名不在白名单内'));

      cspEngine.close();
    });

    test('SystemApi: speak 与 stopSpeak 语音合成调用', () async {
      engine.loadAndExecute('''
        system.speak("Hello Toolbox", { language = "zh-CN", pitch = 1.2, rate = 0.9 }, function(ok)
          state.set("speak_ok", ok)
        end)
        system.stopSpeak(function(ok)
          state.set("stop_speak_ok", ok)
        end)
      ''');

      await _waitFor(() =>
          delegate.getState('speak_ok') != null &&
          delegate.getState('stop_speak_ok') != null);
      expect(delegate.getState('speak_ok'), isTrue);
      expect(delegate.spokenText, 'Hello Toolbox');
      expect(delegate.spokenLanguage, 'zh-CN');
      expect(delegate.spokenPitch, 1.2);
      expect(delegate.spokenRate, 0.9);
      expect(delegate.getState('stop_speak_ok'), isTrue);
      expect(delegate.speechStopped, isTrue);
    });

    test('SocketApi: 无 network 权限拦截与无效连接安全兜底', () {
      final noPermCtx = PluginContext(
        pluginId: 'no_net_plugin',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {},
      );
      final noPermEng = LuaEngine(context: noPermCtx, delegate: delegate);

      // 1. 无 network 权限调用 tcpConnect / tcpSend / tcpClose 报错
      expect(
          () => noPermEng.loadAndExecute('socket.tcpConnect("127.0.0.1", 80)'),
          throwsException);
      expect(() => noPermEng.loadAndExecute('socket.tcpSend("tcp_1", "hi")'),
          throwsException);
      expect(() => noPermEng.loadAndExecute('socket.tcpClose("tcp_1")'),
          throwsException);

      // 2. 无 network 权限调用 udpBind / udpSend / udpClose 报错
      expect(() => noPermEng.loadAndExecute('socket.udpBind(0, {})'),
          throwsException);
      expect(
          () => noPermEng
              .loadAndExecute('socket.udpSend("udp_1", "127.0.0.1", 80, "hi")'),
          throwsException);
      expect(() => noPermEng.loadAndExecute('socket.udpClose("udp_1")'),
          throwsException);

      noPermEng.close();
    });

    test('SocketApi: 活跃连接管理与不存在的套接字安全返回 false', () {
      final netCtx = PluginContext(
        pluginId: 'net_plugin',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {PluginPermission.network},
      );
      final netEng = LuaEngine(context: netCtx, delegate: delegate);

      // tcpSend / tcpClose 不存在的 socketId 返回 false
      netEng.loadAndExecute('''
        state.set("tcp_send_fake", socket.tcpSend("non_exist_id", "data"))
        state.set("tcp_close_fake", socket.tcpClose("non_exist_id"))
        state.set("udp_send_fake", socket.udpSend("non_exist_id", "1.1.1.1", 53, "data"))
        state.set("udp_close_fake", socket.udpClose("non_exist_id"))
      ''');

      expect(delegate.getState('tcp_send_fake'), isFalse);
      expect(delegate.getState('tcp_close_fake'), isFalse);
      expect(delegate.getState('udp_send_fake'), isFalse);
      expect(delegate.getState('udp_close_fake'), isFalse);

      netEng.close();
    });

    test('WebSocketApi: 无权限拦截与格式错误/未知连接安全防御', () {
      final noPermCtx = PluginContext(
        pluginId: 'no_ws_plugin',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {},
      );
      final noPermEng = LuaEngine(context: noPermCtx, delegate: delegate);

      // 1. 无 network 权限调用 websocket 接口报错
      expect(
          () => noPermEng
              .loadAndExecute('websocket.connect("ws://echo.websocket.org")'),
          throwsException);
      expect(() => noPermEng.loadAndExecute('websocket.send("ws_1", "hi")'),
          throwsException);
      expect(() => noPermEng.loadAndExecute('websocket.close("ws_1")'),
          throwsException);

      noPermEng.close();

      // 2. 有权限时对格式错误与未知 wsId 安全处理
      final netCtx = PluginContext(
        pluginId: 'ws_plugin',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {PluginPermission.network},
      );
      final netEng = LuaEngine(context: netCtx, delegate: delegate);

      netEng.loadAndExecute('''
        state.set("ws_send_fake", websocket.send("ws_unknown", "data"))
        state.set("ws_close_fake", websocket.close("ws_unknown"))
      ''');

      expect(delegate.getState('ws_send_fake'), isFalse);
      expect(delegate.getState('ws_close_fake'), isFalse);

      netEng.close();
    });
  });
}
