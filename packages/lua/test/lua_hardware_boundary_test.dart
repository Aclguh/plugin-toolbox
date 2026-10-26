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

/// 模拟外设操作返回失败/空值的 Delegate
class FailingPeripheralDelegate extends MockLuaHostDelegate {
  @override
  Future<bool> stopBluetoothScan() async => false;

  @override
  Future<bool> disconnectBluetooth(String deviceId) async => false;

  @override
  Future<bool> startBluetoothScan(
          void Function(Map<String, dynamic>) onDeviceFound) async =>
      false;

  @override
  Future<bool> connectBluetooth(String deviceId) async => false;

  @override
  Future<String?> readBluetoothCharacteristic(
          String deviceId, String serviceUuid, String charUuid) async =>
      null;

  @override
  Future<bool> writeBluetoothCharacteristic(String deviceId, String serviceUuid,
          String charUuid, String value) async =>
      false;

  @override
  Future<Map<String, dynamic>?> readNdef() async => null;

  @override
  Future<bool> writeNdef(List<Map<String, dynamic>> records) async => false;

  @override
  Future<Map<String, dynamic>?> getCurrentPosition() async => null;

  @override
  Future<bool> playAudio(String filePath) async => false;

  @override
  Future<bool> startAudioRecording(String destPath) async => false;
}

/// 模拟外设异常崩溃/断开连接的 Delegate
class ThrowingPeripheralDelegate extends MockLuaHostDelegate {
  @override
  Future<bool> connectBluetooth(String deviceId) async =>
      throw Exception('BLE connection timeout');

  @override
  Future<String?> readBluetoothCharacteristic(
          String deviceId, String serviceUuid, String charUuid) async =>
      throw Exception('BLE read characteristic failed');

  @override
  Future<bool> writeBluetoothCharacteristic(String deviceId, String serviceUuid,
          String charUuid, String value) async =>
      throw Exception('BLE write characteristic failed');

  @override
  Future<Map<String, dynamic>?> readNdef() async =>
      throw Exception('NFC hardware failure');

  @override
  Future<bool> writeNdef(List<Map<String, dynamic>> records) async =>
      throw Exception('NFC tag detached');

  @override
  Future<Map<String, dynamic>?> getCurrentPosition() async =>
      throw Exception('GPS service unavailable');

  @override
  Future<bool> playAudio(String filePath) async =>
      throw Exception('Audio output stream broken');

  @override
  Future<bool> stopAudio() async => throw Exception('Audio engine error');

  @override
  Future<bool> playTone(double frequencyHz, int durationMs) async =>
      throw Exception('DAC channel error');

  @override
  Future<bool> startAudioRecording(String destPath) async =>
      throw Exception('Mic hardware error');

  @override
  Future<Map<String, dynamic>?> stopAudioRecording() async =>
      throw Exception('Codec flush failure');

  @override
  Future<double> getAudioDecibel() async =>
      throw Exception('Audio sensor bus error');
}

void main() {
  group('BluetoothApi 硬件异常与边界分支覆盖测试', () {
    late PluginContext context;

    setUp(() {
      context = PluginContext(
        pluginId: 'ble_boundary_test',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {PluginPermission.bluetooth},
      );
    });

    test('isAvailable 同步调用与异步回调分支', () async {
      final delegate = MockLuaHostDelegate()..bluetoothAvailable = false;
      final engine = LuaEngine(context: context, delegate: delegate);

      // 同步调用返回 false
      engine.loadAndExecute('state.set("sync_avail", bluetooth.isAvailable())');
      expect(delegate.getState('sync_avail'), isFalse);

      // 异步回调
      engine.loadAndExecute('''
        bluetooth.isAvailable(function(avail)
          state.set("async_avail", avail)
        end)
      ''');
      await _waitFor(() => delegate.getState('async_avail') != null);
      expect(delegate.getState('async_avail'), isFalse);

      engine.close();
    });

    test('startScan 失败、stopScan 回调与 disconnect 回调分支', () async {
      final delegate = FailingPeripheralDelegate();
      final engine = LuaEngine(context: context, delegate: delegate);

      engine.loadAndExecute('''
        bluetooth.startScan(function(res)
          state.set("scan_res_ok", res.ok)
          state.set("scan_res_err", res.error)
        end)
        bluetooth.stopScan(function(stopped)
          state.set("stop_res", stopped)
        end)
        bluetooth.disconnect("DEV-01", function(ok)
          state.set("disconnect_res", ok)
        end)
      ''');

      await _waitFor(() =>
          delegate.getState('scan_res_ok') != null &&
          delegate.getState('stop_res') != null &&
          delegate.getState('disconnect_res') != null);

      expect(delegate.getState('scan_res_ok'), isFalse);
      expect(delegate.getState('scan_res_err'), contains('无法启动蓝牙扫描'));
      expect(delegate.getState('stop_res'), isFalse);
      expect(delegate.getState('disconnect_res'), isFalse);

      engine.close();
    });

    test('connect, read, write 失败响应分支 (FailingDelegate)', () async {
      final delegate = FailingPeripheralDelegate();
      final engine = LuaEngine(context: context, delegate: delegate);

      engine.loadAndExecute('''
        bluetooth.connect("DEV_FAIL", function(res)
          state.set("conn_ok", res.ok)
          state.set("conn_err", res.error)
        end)
        bluetooth.read("DEV_FAIL", "SVC", "CHAR", function(res)
          state.set("read_ok", res.ok)
          state.set("read_err", res.error)
        end)
        bluetooth.write("DEV_FAIL", "SVC", "CHAR", "VAL", function(res)
          state.set("write_ok", res.ok)
          state.set("write_err", res.error)
        end)
      ''');

      await _waitFor(() =>
          delegate.getState('conn_ok') != null &&
          delegate.getState('read_ok') != null &&
          delegate.getState('write_ok') != null);

      expect(delegate.getState('conn_ok'), isFalse);
      expect(delegate.getState('conn_err'), contains('连接 BLE 设备失败'));
      expect(delegate.getState('read_ok'), isFalse);
      expect(delegate.getState('read_err'), contains('读取特征值失败'));
      expect(delegate.getState('write_ok'), isFalse);
      expect(delegate.getState('write_err'), contains('写入特征值失败'));

      engine.close();
    });

    test('connect, read, write 异常捕获分支 (ThrowingDelegate)', () async {
      final delegate = ThrowingPeripheralDelegate();
      final engine = LuaEngine(context: context, delegate: delegate);

      engine.loadAndExecute('''
        bluetooth.connect("DEV_EX", function(res)
          state.set("ex_conn_ok", res.ok)
          state.set("ex_conn_err", res.error)
        end)
        bluetooth.read("DEV_EX", "SVC", "CHAR", function(res)
          state.set("ex_read_ok", res.ok)
          state.set("ex_read_err", res.error)
        end)
        bluetooth.write("DEV_EX", "SVC", "CHAR", "VAL", function(res)
          state.set("ex_write_ok", res.ok)
          state.set("ex_write_err", res.error)
        end)
      ''');

      await _waitFor(() =>
          delegate.getState('ex_conn_ok') != null &&
          delegate.getState('ex_read_ok') != null &&
          delegate.getState('ex_write_ok') != null);

      expect(delegate.getState('ex_conn_ok'), isFalse);
      expect(
          delegate.getState('ex_conn_err'), contains('BLE connection timeout'));
      expect(delegate.getState('ex_read_ok'), isFalse);
      expect(delegate.getState('ex_read_err'),
          contains('BLE read characteristic failed'));
      expect(delegate.getState('ex_write_ok'), isFalse);
      expect(delegate.getState('ex_write_err'),
          contains('BLE write characteristic failed'));

      engine.close();
    });
  });

  group('NfcApi 硬件异常与边界分支覆盖测试', () {
    late PluginContext context;

    setUp(() {
      context = PluginContext(
        pluginId: 'nfc_boundary_test',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {PluginPermission.nfc},
      );
    });

    test('isAvailable 同步与异步分支', () async {
      final delegate = MockLuaHostDelegate()..nfcAvailable = false;
      final engine = LuaEngine(context: context, delegate: delegate);

      engine.loadAndExecute('state.set("nfc_sync", nfc.isAvailable())');
      expect(delegate.getState('nfc_sync'), isFalse);

      engine.loadAndExecute('''
        nfc.isAvailable(function(avail)
          state.set("nfc_async", avail)
        end)
      ''');
      await _waitFor(() => delegate.getState('nfc_async') != null);
      expect(delegate.getState('nfc_async'), isFalse);

      engine.close();
    });

    test('readNdef 与 writeNdef 失败与超时分支', () async {
      final delegate = FailingPeripheralDelegate();
      final engine = LuaEngine(context: context, delegate: delegate);

      engine.loadAndExecute('''
        nfc.readNdef(function(res)
          state.set("read_ok", res.ok)
          state.set("read_err", res.error)
        end)
        nfc.writeNdef({ { type = "text", payload = "fail" } }, function(res)
          state.set("write_ok", res.ok)
          state.set("write_err", res.error)
        end)
      ''');

      await _waitFor(() =>
          delegate.getState('read_ok') != null &&
          delegate.getState('write_ok') != null);

      expect(delegate.getState('read_ok'), isFalse);
      expect(delegate.getState('read_err'), contains('未感应到 NFC 标签或读取超时'));
      expect(delegate.getState('write_ok'), isFalse);
      expect(delegate.getState('write_err'), contains('NFC 标签写入失败'));

      engine.close();
    });

    test('readNdef 与 writeNdef 异常捕获分支', () async {
      final delegate = ThrowingPeripheralDelegate();
      final engine = LuaEngine(context: context, delegate: delegate);

      engine.loadAndExecute('''
        nfc.readNdef(function(res)
          state.set("read_ex_ok", res.ok)
          state.set("read_ex_err", res.error)
        end)
        nfc.writeNdef({ { type = "text", payload = "ex" } }, function(res)
          state.set("write_ex_ok", res.ok)
          state.set("write_ex_err", res.error)
        end)
      ''');

      await _waitFor(() =>
          delegate.getState('read_ex_ok') != null &&
          delegate.getState('write_ex_ok') != null);

      expect(delegate.getState('read_ex_ok'), isFalse);
      expect(
          delegate.getState('read_ex_err'), contains('NFC hardware failure'));
      expect(delegate.getState('write_ex_ok'), isFalse);
      expect(delegate.getState('write_ex_err'), contains('NFC tag detached'));

      engine.close();
    });
  });

  group('LocationApi 硬件异常与边界分支覆盖测试', () {
    late PluginContext context;

    setUp(() {
      context = PluginContext(
        pluginId: 'location_boundary_test',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {PluginPermission.location},
      );
    });

    test('isAvailable 同步与异步分支', () async {
      final delegate = MockLuaHostDelegate()..locationAvailable = false;
      final engine = LuaEngine(context: context, delegate: delegate);

      engine.loadAndExecute('state.set("loc_sync", location.isAvailable())');
      expect(delegate.getState('loc_sync'), isFalse);

      engine.loadAndExecute('''
        location.isAvailable(function(avail)
          state.set("loc_async", avail)
        end)
      ''');
      await _waitFor(() => delegate.getState('loc_async') != null);
      expect(delegate.getState('loc_async'), isFalse);

      engine.close();
    });

    test('getCurrentPosition 与 getAltitude 为空降级', () async {
      final delegate = FailingPeripheralDelegate();
      final engine = LuaEngine(context: context, delegate: delegate);

      engine.loadAndExecute('''
        location.getCurrentPosition(function(res)
          state.set("loc_pos_ok", res.ok)
          state.set("loc_pos_err", res.error)
        end)
        location.getAltitude(function(alt)
          state.set("loc_alt", alt)
        end)
      ''');

      await _waitFor(() =>
          delegate.getState('loc_pos_ok') != null &&
          delegate.getState('loc_alt') != null);

      expect(delegate.getState('loc_pos_ok'), isFalse);
      expect(delegate.getState('loc_pos_err'), contains('无法获取当前位置信息'));
      expect(delegate.getState('loc_alt'), 0.0);

      engine.close();
    });

    test('getCurrentPosition 与 getAltitude 异常捕获', () async {
      final delegate = ThrowingPeripheralDelegate();
      final engine = LuaEngine(context: context, delegate: delegate);

      engine.loadAndExecute('''
        location.getCurrentPosition(function(res)
          state.set("loc_ex_ok", res.ok)
          state.set("loc_ex_err", res.error)
        end)
        location.getAltitude(function(alt)
          state.set("loc_ex_alt", alt)
        end)
      ''');

      await _waitFor(() =>
          delegate.getState('loc_ex_ok') != null &&
          delegate.getState('loc_ex_alt') != null);

      expect(delegate.getState('loc_ex_ok'), isFalse);
      expect(
          delegate.getState('loc_ex_err'), contains('GPS service unavailable'));
      expect(delegate.getState('loc_ex_alt'), 0.0);

      engine.close();
    });
  });

  group('AudioApi 硬件异常与边界分支覆盖测试', () {
    late PluginContext context;
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('ptx_audio_test_');
      context = PluginContext(
        pluginId: 'audio_boundary_test',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        rootDir: tempDir,
        grantedPermissions: {
          PluginPermission.storage,
          PluginPermission.microphone,
        },
      );
    });

    tearDown(() async {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('playAudio, stopAudio 与 playTone 异常与状态降级', () async {
      final delegate = ThrowingPeripheralDelegate();
      final engine = LuaEngine(context: context, delegate: delegate);

      // 带回调调用
      engine.loadAndExecute('''
        audio.play("sound.mp3", function(ok)
          state.set("play_cb_ok", ok)
        end)
        audio.stop(function(ok)
          state.set("stop_cb_ok", ok)
        end)
        audio.playTone(440, 200, function(ok)
          state.set("tone_cb_ok", ok)
        end)
      ''');

      await _waitFor(() =>
          delegate.getState('play_cb_ok') != null &&
          delegate.getState('stop_cb_ok') != null &&
          delegate.getState('tone_cb_ok') != null);

      expect(delegate.getState('play_cb_ok'), isFalse);
      expect(delegate.getState('stop_cb_ok'), isFalse);
      expect(delegate.getState('tone_cb_ok'), isFalse);

      // 不带回调的直接调用
      engine.loadAndExecute('''
        audio.play("sound.mp3")
        audio.stop()
      ''');

      await _waitFor(() => delegate.getState('__audio_playing') == false);
      expect(delegate.getState('__audio_playing'), isFalse);

      engine.close();
    });

    test('startRecord, stopRecord 与 getDecibel 异常与状态降级', () async {
      final delegate = ThrowingPeripheralDelegate();
      final engine = LuaEngine(context: context, delegate: delegate);

      // 带回调异常分支
      engine.loadAndExecute('''
        audio.startRecord("rec.m4a", function(ok)
          state.set("rec_cb_ok", ok)
        end)
        audio.stopRecord(function(info)
          state.set("stop_info", info == nil)
        end)
        audio.getDecibel(function(db)
          state.set("decibel_val", db)
        end)
      ''');

      await _waitFor(() =>
          delegate.getState('rec_cb_ok') != null &&
          delegate.getState('stop_info') != null &&
          delegate.getState('decibel_val') != null);

      expect(delegate.getState('rec_cb_ok'), isFalse);
      expect(delegate.getState('stop_info'), isTrue);
      expect(delegate.getState('decibel_val'), 0.0);

      // 无回调正常更新状态
      final normalDelegate = MockLuaHostDelegate();
      final normalEngine =
          LuaEngine(context: context, delegate: normalDelegate);
      normalEngine.loadAndExecute('''
        audio.getDecibel()
        audio.startRecord("rec2.m4a")
      ''');

      await _waitFor(() =>
          normalDelegate.getState('__audio_decibel') != null &&
          normalDelegate.getState('__audio_recording') != null);

      expect(normalDelegate.getState('__audio_decibel'),
          normalDelegate.mockDecibel);
      expect(normalDelegate.getState('__audio_recording'), isTrue);

      normalEngine.close();
      engine.close();
    });

    test('ApiGuard 统一权限审计轨迹验证', () async {
      final delegate = MockLuaHostDelegate();
      final engine = LuaEngine(context: context, delegate: delegate);
      engine.loadAndExecute('''
        audio.getDecibel(function() end)
        audio.play("sound.mp3", function() end)
        audio.startRecord("rec.m4a", function() end)
      ''');
      await _waitFor(() => context.auditTrail.length >= 3);
      final actions = context.auditTrail.map((a) => a.action).toList();
      expect(actions, contains('audio.getDecibel'));
      expect(actions, contains('audio.play'));
      expect(actions, contains('audio.startRecord'));
      engine.close();
    });
  });
  group('DialogApi 边界分支与参数形态测试', () {
    late PluginContext context;
    late MockLuaHostDelegate delegate;
    late LuaEngine engine;

    setUp(() {
      delegate = MockLuaHostDelegate();
      context = PluginContext(
        pluginId: 'dialog_test',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: const {},
      );
      engine = LuaEngine(context: context, delegate: delegate);
    });

    tearDown(() => engine.close());

    test('pickDate 与 pickTime 支持 table 参数形式与状态写入', () async {
      engine.loadAndExecute('''
        dialog.pickDate({ initialDate = "2025-01-01", firstDate = "2020-01-01", lastDate = "2030-12-31" })
        dialog.pickTime({ initialTime = "14:30" })
      ''');
      await _waitFor(() =>
          delegate.getState('__dialog_date') != null &&
          delegate.getState('__dialog_time') != null);
      expect(delegate.getState('__dialog_date'), '2025-06-15');
      expect(delegate.getState('__dialog_time'), '15:45');
    });

    test('prompt 支持 table 参数形式与回调传递', () async {
      engine.loadAndExecute('''
        dialog.prompt({ title = "提示", hint = "输入项", defaultValue = "默认值" }, function(res)
          state.set("prompt_res", res)
        end)
      ''');
      await _waitFor(() => delegate.getState('prompt_res') != null);
      expect(delegate.getState('prompt_res'), 'user-inputted-text');
    });

    test('pickItem 与 bottomSheet 支持列表选择与回调传递', () async {
      engine.loadAndExecute('''
        dialog.pickItem("选择模式", { "模式A", "模式B" }, 1, function(text, idx)
          state.set("picked_text", text)
          state.set("picked_idx", idx)
        end)
        dialog.bottomSheet("底部选项", { "选项1", "选项2" }, function(text, idx)
          state.set("sheet_text", text)
          state.set("sheet_idx", idx)
        end)
      ''');
      await _waitFor(() =>
          delegate.getState('picked_text') != null &&
          delegate.getState('sheet_text') != null);
      expect(delegate.getState('picked_text'), 'Option 2');
      expect(delegate.getState('picked_idx'), 2);
      expect(delegate.getState('sheet_text'), 'Item 1');
      expect(delegate.getState('sheet_idx'), 1);
    });
  });

  group('FS Binary & System API 边界分支覆盖测试', () {
    late PluginContext context;
    late Directory tempDir;
    late MockLuaHostDelegate delegate;
    late LuaEngine engine;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('ptx_fs_bin_');
      delegate = MockLuaHostDelegate();
      context = PluginContext(
        pluginId: 'fs_bin_test',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        rootDir: tempDir,
        grantedPermissions: {
          PluginPermission.storage,
          PluginPermission.screen,
        },
      );
      engine = LuaEngine(context: context, delegate: delegate);
    });

    tearDown(() async {
      engine.close();
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('fs 十六进制读写与移动复制', () {
      engine.loadAndExecute('''
        fs.writeHex("bin.dat", "4142434445")
        local hex = fs.readHex("bin.dat")
        state.set("hex_val", hex)
        fs.copy("bin.dat", "bin_copy.dat")
        fs.move("bin_copy.dat", "bin_moved.dat")
        state.set("moved_exists", fs.exists("bin_moved.dat"))
      ''');

      expect(delegate.getState('hex_val'), '4142434445');
      expect(delegate.getState('moved_exists'), isTrue);
    });

    test('system 设备状态与屏幕控制', () async {
      engine.loadAndExecute('''
        state.set("battery", system.batteryLevel())
        state.set("charging", system.isCharging())
        state.set("net_type", system.networkType())
        system.setKeepScreenOn(true)
        system.setBrightness(0.8)
        state.set("bright_val", system.brightness())
      ''');

      await _waitFor(() => delegate.getState('bright_val') != null);
      expect(delegate.getState('battery'), 85);
      expect(delegate.getState('charging'), isTrue);
      expect(delegate.getState('net_type'), 'wifi');
      expect(delegate.keepScreenOn, isTrue);
      expect(delegate.screenBrightness, 0.8);
      expect(delegate.getState('bright_val'), 'light');
    });

    test('fs Base64 同步与异步读写', () async {
      engine.loadAndExecute('''
        fs.writeBase64("b64_sync.txt", "SGVsbG8gV29ybGQ=")
        state.set("b64_sync_read", fs.readBase64("b64_sync.txt"))

        fs.writeBase64("b64_async.txt", "data:text/plain;base64,VGVzdA==", function(ok)
          state.set("b64_write_ok", ok)
          fs.readBase64("b64_async.txt", function(data)
            state.set("b64_async_data", data)
          end)
        end)
      ''');

      await _waitFor(() =>
          delegate.getState('b64_sync_read') != null &&
          delegate.getState('b64_write_ok') != null &&
          delegate.getState('b64_async_data') != null);

      expect(delegate.getState('b64_sync_read'), 'SGVsbG8gV29ybGQ=');
      expect(delegate.getState('b64_write_ok'), isTrue);
      expect(delegate.getState('b64_async_data'), 'VGVzdA==');
    });
  });

  group('Socket 与 WebSocket 边界分支覆盖测试', () {
    late PluginContext context;
    late MockLuaHostDelegate delegate;
    late LuaEngine engine;

    setUp(() {
      delegate = MockLuaHostDelegate();
      context = PluginContext(
        pluginId: 'socket_boundary_test',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {PluginPermission.network},
      );
      engine = LuaEngine(context: context, delegate: delegate);
    });

    tearDown(() => engine.close());

    test('socket 与 websocket 创建句柄与事件回调', () async {
      engine.loadAndExecute('''
        local sId = socket.tcpConnect("127.0.0.1", 65530, {
          onError = function(err)
            state.set("sock_err", err ~= nil)
          end
        })
        state.set("sock_id", sId ~= nil)

        local wsId = websocket.connect("ws://127.0.0.1:65530/test", {
          onError = function(err)
            state.set("ws_err", err ~= nil)
          end
        })
        state.set("ws_id", wsId ~= nil)
      ''');

      await _waitFor(() =>
          delegate.getState('sock_id') != null &&
          delegate.getState('ws_id') != null);

      expect(delegate.getState('sock_id'), isTrue);
      expect(delegate.getState('ws_id'), isTrue);
    });

    test('socket 与 websocket 数据发送与关闭非活跃句柄', () {
      engine.loadAndExecute('''
        state.set("tcp_send_str", socket.tcpSend("invalid_sock", "hello"))
        state.set("tcp_send_tbl", socket.tcpSend("invalid_sock", { 1, 2, 3 }))
        state.set("tcp_close_invalid", socket.tcpClose("invalid_sock"))
        state.set("ws_send_invalid", websocket.send("invalid_ws", "msg"))
        state.set("ws_close_invalid", websocket.close("invalid_ws"))
      ''');

      expect(delegate.getState('tcp_send_str'), isFalse);
      expect(delegate.getState('tcp_send_tbl'), isFalse);
      expect(delegate.getState('tcp_close_invalid'), isFalse);
      expect(delegate.getState('ws_send_invalid'), isFalse);
      expect(delegate.getState('ws_close_invalid'), isFalse);
    });
  });
  group('Image, Camera & Screen APIs 状态写入与异常降级', () {
    late PluginContext context;
    late Directory tempDir;
    late MockLuaHostDelegate delegate;
    late LuaEngine engine;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('ptx_img_cam_');
      delegate = MockLuaHostDelegate();
      context = PluginContext(
        pluginId: 'img_cam_test',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        rootDir: tempDir,
        grantedPermissions: {
          PluginPermission.storage,
          PluginPermission.camera,
          PluginPermission.screen,
        },
      );
      engine = LuaEngine(context: context, delegate: delegate);
    });

    tearDown(() async {
      engine.close();
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('image.info, compress, crop, convert 与 stripExif 无回调状态写入', () async {
      engine.loadAndExecute('''
        image.info("pic.jpg")
        image.compress("pic.jpg", 75)
        image.crop("pic.jpg", 10, 10, 100, 100)
        image.convert("pic.png", "jpeg")
        image.stripExif("pic.jpg")
      ''');

      await _waitFor(() =>
          delegate.getState('__image_info') != null &&
          delegate.getState('__compressed_image') != null &&
          delegate.getState('__cropped_image') != null &&
          delegate.getState('__converted_image') != null &&
          delegate.getState('__clean_image') != null);

      expect(delegate.getState('__image_info'), isNotNull);
      expect(
          delegate.getState('__compressed_image'), contains('_compressed.jpg'));
      expect(delegate.getState('__cropped_image'), contains('_cropped'));
      expect(
          delegate.getState('__converted_image'), contains('_converted.jpg'));
      expect(delegate.getState('__clean_image'), contains('_clean.jpg'));
    });

    test('camera.takePhoto 与 screen.capture 写入与回调', () async {
      engine.loadAndExecute('''
        camera.takePhoto()
        screen.capture(function(path)
          state.set("screen_captured", path)
        end)
      ''');

      await _waitFor(() =>
          delegate.getState('__captured_photo') != null &&
          delegate.getState('screen_captured') != null);

      expect(delegate.getState('__captured_photo'), contains('camera/photo_'));
      expect(
          delegate.getState('screen_captured'), contains('captures/screen_'));
    });
  });
}
