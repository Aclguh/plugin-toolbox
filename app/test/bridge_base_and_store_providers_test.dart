import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:plugin_toolbox/src/plugin_host/plugin_host_system_delegate.dart';
import 'package:plugin_toolbox/src/plugin_host/plugin_native_bridge.dart';
import 'package:plugin_toolbox/src/plugin_store/store_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TestBridge extends NativeBridgeBase {
  TestBridge({
    required super.pluginRootDir,
    super.storageQuotaMb = 50,
    super.nativeChannel,
    super.logger,
  });
}

class TestSystemDelegate with PluginHostSystemDelegate {
  @override
  final PluginNativeBridge nativeBridge;
  TestSystemDelegate(this.nativeBridge);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    tempDir = Directory.systemTemp.createTempSync('bridge_test_');
  });

  tearDown(() {
    try {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    } catch (_) {}
  });

  group('NativeBridgeBase 基础设施与安全路径/配额校验', () {
    test('sanitizePickedFileName 净化文件名分隔符与路径穿越', () {
      expect(NativeBridgeBase.sanitizePickedFileName('foo/bar\\baz.txt'),
          'foo_bar_baz.txt');
      expect(NativeBridgeBase.sanitizePickedFileName('evil..name.txt'),
          'evil_name.txt');
      expect(NativeBridgeBase.sanitizePickedFileName('   '), 'picked_file');
      expect(NativeBridgeBase.sanitizePickedFileName('normal.json'),
          'normal.json');
    });

    test('uniqueSandboxFileName 重名自动追加递增序号', () {
      final fileA = File('${tempDir.path}/demo.txt');
      fileA.writeAsStringSync('hello');

      final unique1 =
          NativeBridgeBase.uniqueSandboxFileName(tempDir, 'demo.txt');
      expect(unique1, 'demo(1).txt');

      final fileB = File('${tempDir.path}/demo(1).txt');
      fileB.writeAsStringSync('hello 1');

      final unique2 =
          NativeBridgeBase.uniqueSandboxFileName(tempDir, 'demo.txt');
      expect(unique2, 'demo(2).txt');

      expect(NativeBridgeBase.uniqueSandboxFileName(tempDir, 'not_exist.txt'),
          'not_exist.txt');
    });

    test('calculateSandboxUsedBytes, sandboxUsedBytes 与缓存增量更新', () async {
      final bridge = TestBridge(
        pluginRootDir: tempDir,
        storageQuotaMb: 1, // 1MB
        logger: Logger(),
      );

      expect(bridge.sandboxUsedBytes(), 0);
      expect(await bridge.calculateSandboxUsedBytes(), 0);

      // 写入测试文件 100 字节
      final subFile = File('${tempDir.path}/test.bin');
      subFile.writeAsBytesSync(List.filled(100, 1));

      // 首次计算刷新缓存
      final newBridge = TestBridge(pluginRootDir: tempDir, storageQuotaMb: 1);
      final used = await newBridge.calculateSandboxUsedBytes();
      expect(used, 100);
      expect(newBridge.sandboxUsedBytes(), 100);

      // 增量更新与下限保护
      newBridge.updateSandboxUsedBytes(50);
      expect(newBridge.sandboxUsedBytes(), 150);
      newBridge.updateSandboxUsedBytes(-300);
      expect(newBridge.sandboxUsedBytes(), 0);

      // 配额校验
      expect(newBridge.hasSandboxQuotaFor(500), isTrue);
      expect(await newBridge.hasSandboxQuotaForAsync(500), isTrue);
      expect(newBridge.hasSandboxQuotaFor(2 * 1024 * 1024), isFalse);
      expect(await newBridge.hasSandboxQuotaForAsync(2 * 1024 * 1024), isFalse);
    });

    test('resolveSandboxPath 沙箱越界防御与规范路径解析', () {
      final bridge = TestBridge(pluginRootDir: tempDir);

      expect(bridge.resolveSandboxPath('', 'testOp'), isNull);
      expect(bridge.resolveSandboxPath('sub/file.txt', 'testOp'),
          '${tempDir.path}/sub/file.txt');
      expect(bridge.resolveSandboxPath('../../etc/passwd', 'testOp'), isNull);

      // 绝对路径检查
      final insideAbs = '${tempDir.path}/data/f.txt';
      expect(bridge.resolveSandboxPath(insideAbs, 'testOp'), insideAbs);
      final outsideAbs = '${Directory.systemTemp.path}/outside.txt';
      expect(bridge.resolveSandboxPath(outsideAbs, 'testOp'), isNull);
    });

    test('invoke 与 invokeMap 异常降级兜底', () async {
      const channel = MethodChannel('fake_channel_not_registered');
      final bridge = TestBridge(
        pluginRootDir: tempDir,
        nativeChannel: channel,
        logger: Logger(),
      );

      final res = await bridge.invoke<bool>('missing_method', false);
      expect(res, isFalse);

      final mapRes = await bridge.invokeMap('missing_method');
      expect(mapRes, isNull);
    });
  });

  group('PluginRepositoryNotifier 多仓库源与持久化', () {
    test('默认官方仓库源配置与自定义仓库增删切换', () async {
      final prefs = await SharedPreferences.getInstance();
      final notifier = PluginRepositoryNotifier(prefs);

      expect(notifier.state.isDefault, isTrue);
      expect(notifier.savedConfigs.length, 1);
      expect(notifier.savedConfigs.first.isDefault, isTrue);

      // 设置自定义仓库
      final success = await notifier
          .setRepository('https://github.com/CustomDev/my-plugins');
      expect(success, isTrue);
      expect(notifier.state.owner, 'CustomDev');
      expect(notifier.state.repository, 'my-plugins');
      expect(notifier.savedConfigs.length, 2);
      expect(prefs.getString(PluginRepositoryNotifier.customRepoKey),
          'https://github.com/CustomDev/my-plugins');

      // 输入非法 URL
      final invalid =
          await notifier.setRepository('invalid://not-a-github-repo');
      expect(invalid, isFalse);

      // 移除已保存的源
      final addedConfig = notifier.state;
      await notifier.removeSavedRepository(addedConfig);
      expect(notifier.savedConfigs.length, 1);
      expect(notifier.state.isDefault, isTrue);

      // 空字符串重置为默认
      await notifier.setRepository('https://github.com/Other/repo');
      expect(notifier.state.isDefault, isFalse);
      await notifier.setRepository('');
      expect(notifier.state.isDefault, isTrue);
    });
  });

  group('PluginHostSystemDelegate 宿主系统委托透传', () {
    test('方法转发至 PluginNativeBridge', () async {
      final bridge = PluginNativeBridge(pluginRootDir: tempDir);
      final delegate = TestSystemDelegate(bridge);

      expect(() => delegate.shareText('hello'), returnsNormally);
      expect(await delegate.openUrl('https://example.com'), isFalse);
      expect(await delegate.setTorch(true), isFalse);
      expect(delegate.isTorchOn, isFalse);
      expect(await delegate.startSensor('accel'), isFalse);
      expect(await delegate.stopSensor('accel'), isFalse);
      expect(await delegate.getSensorData('accel'), isNull);
      expect(await delegate.showNotification(title: 't', body: 'b'), -1);
      expect(
          await delegate.scheduleNotification(
              title: 't', body: 'b', delaySeconds: 1),
          -1);
      expect(await delegate.cancelNotification(1), isFalse);
      expect(await delegate.cancelAllNotifications(), isFalse);
      expect(await delegate.setKeepScreenOn(true), isFalse);
      expect(await delegate.setBrightness(0.5), isFalse);
      expect(await delegate.getBrightness(), 1.0);
      expect(await delegate.resetBrightness(), isFalse);

      expect(() => delegate.batteryLevel, throwsUnimplementedError);
      expect(() => delegate.isCharging, throwsUnimplementedError);
      expect(() => delegate.networkType, throwsUnimplementedError);
      expect(() => delegate.checkIsCharging(), throwsUnimplementedError);
      expect(await delegate.getBatteryLevel(), -1);
      expect(await delegate.fetchNetworkType(), 'unknown');
      expect(await delegate.getInitialShare(), isNull);
      expect(await delegate.isBiometricsAvailable(), isFalse);
      expect((await delegate.authenticateBiometrics())['success'], isFalse);
      expect(await delegate.isLocationAvailable(), isFalse);
      expect(await delegate.getCurrentPosition(), isNull);
      expect(await delegate.isNfcAvailable(), isFalse);
      expect(await delegate.readNdef(), isNull);
      expect(await delegate.writeNdef([]), isFalse);
      expect(await delegate.isBluetoothAvailable(), isFalse);
      expect(await delegate.startBluetoothScan((_) {}), isFalse);
      expect(await delegate.stopBluetoothScan(), isFalse);
      expect(await delegate.connectBluetooth('id'), isFalse);
      expect(await delegate.disconnectBluetooth('id'), isFalse);
      expect(
          await delegate.readBluetoothCharacteristic('id', 's', 'c'), isNull);
      expect(await delegate.writeBluetoothCharacteristic('id', 's', 'c', 'v'),
          isFalse);
      expect(await delegate.getWifiInfo(), isNull);
      expect((await delegate.pingHost('127.0.0.1'))['ok'], isFalse);
    });
  });
}
