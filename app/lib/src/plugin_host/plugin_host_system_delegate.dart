import 'dart:ui';
import 'plugin_native_bridge.dart';

/// LuaHostDelegate 的系统能力域方法集：分享/链接、手电筒、传感器、
/// 通知、屏幕控制、电池与网络状态、生物认证、定位、NFC 与蓝牙。
///
/// 全部为桥接层的同构转发；对于宿主无低成本真实数据源的同步假值 API
/// （batteryLevel / isCharging / networkType / checkIsCharging），
/// 改为抛出 UnimplementedError，让 Lua 侧 pcall 可探测降级，
/// 而不是返回误导性常量。
mixin PluginHostSystemDelegate {
  PluginNativeBridge get nativeBridge;

  Future<void> shareText(String text, {String? subject}) =>
      nativeBridge.shareText(text, subject: subject);

  Future<bool> openUrl(String url) => nativeBridge.openUrl(url);

  Future<bool> setTorch(bool enabled) => nativeBridge.setTorch(enabled);

  bool get isTorchOn => nativeBridge.isTorchOn;

  Future<bool> startSensor(String type) => nativeBridge.startSensor(type);

  Future<bool> stopSensor(String type) => nativeBridge.stopSensor(type);

  Future<Map<String, dynamic>?> getSensorData(String type) =>
      nativeBridge.getSensorData(type);

  Future<int> showNotification(
          {required String title, required String body, String? payload}) =>
      nativeBridge.showNotification(title: title, body: body, payload: payload);

  Future<int> scheduleNotification(
          {required String title,
          required String body,
          required int delaySeconds,
          String? payload}) =>
      nativeBridge.scheduleNotification(
          title: title,
          body: body,
          delaySeconds: delaySeconds,
          payload: payload);

  Future<bool> cancelNotification(int id) =>
      nativeBridge.cancelNotification(id);

  Future<bool> cancelAllNotifications() =>
      nativeBridge.cancelAllNotifications();

  Future<bool> setKeepScreenOn(bool enabled) =>
      nativeBridge.setKeepScreenOn(enabled);

  Future<bool> setBrightness(double brightness) =>
      nativeBridge.setBrightness(brightness);

  Future<double> getBrightness() => nativeBridge.getBrightness();

  Future<bool> resetBrightness() => nativeBridge.resetBrightness();

  ({int width, int height, double pixelRatio}) getScreenMetrics() {
    final view = PlatformDispatcher.instance.implicitView;
    if (view == null) return (width: 0, height: 0, pixelRatio: 1.0);
    final size = view.physicalSize;
    return (
      width: size.width.round(),
      height: size.height.round(),
      pixelRatio: view.devicePixelRatio,
    );
  }

  String getSystemLocale() => PlatformDispatcher.instance.locale.toString();

  String getSystemBrightness() =>
      PlatformDispatcher.instance.platformBrightness == Brightness.dark
          ? 'dark'
          : 'light';

  // 同步电量读取没有低成本真实来源（未引入 battery_plus 等原生依赖），
  // 抛出让 Lua 绑定以脚本错误呈现；真实值请走带回调的异步链路
  int get batteryLevel => throw UnimplementedError(
      'batteryLevel 同步读取不受支持，请使用带回调的 system.batteryLevel(cb) 异步获取');

  bool get isCharging =>
      throw UnimplementedError('isCharging 同步读取不受支持：宿主未提供充电状态能力');

  String get networkType => throw UnimplementedError(
      'networkType 同步读取不受支持，请使用带回调的 system.networkType(cb) 异步获取');

  Future<int> getBatteryLevel() => nativeBridge.getBatteryLevel();

  // 必须同步抛出（而非返回失败 Future）：Lua 绑定对失败 Future 会回落到
  // 同样抛异常的同步 getter，造成未处理的异步异常
  Future<bool> checkIsCharging() {
    throw UnimplementedError('checkIsCharging 未实现：宿主未提供充电状态能力');
  }

  Future<String> fetchNetworkType() => nativeBridge.fetchNetworkType();

  Future<Map<String, dynamic>?> getInitialShare() =>
      nativeBridge.getInitialShare();

  Future<bool> isBiometricsAvailable() => nativeBridge.isBiometricsAvailable();

  Future<Map<String, dynamic>> authenticateBiometrics({String? reason}) =>
      nativeBridge.authenticateBiometrics(reason: reason);

  Future<bool> isLocationAvailable() => nativeBridge.isLocationAvailable();

  Future<Map<String, dynamic>?> getCurrentPosition() =>
      nativeBridge.getCurrentPosition();

  Future<bool> isNfcAvailable() => nativeBridge.isNfcAvailable();

  Future<Map<String, dynamic>?> readNdef() => nativeBridge.readNdef();

  Future<bool> writeNdef(List<Map<String, dynamic>> records) =>
      nativeBridge.writeNdef(records);

  Future<bool> isBluetoothAvailable() => nativeBridge.isBluetoothAvailable();

  Future<bool> startBluetoothScan(
          void Function(Map<String, dynamic> device) onDeviceFound) =>
      nativeBridge.startBluetoothScan(onDeviceFound);

  Future<bool> stopBluetoothScan() => nativeBridge.stopBluetoothScan();

  Future<bool> connectBluetooth(String deviceId) =>
      nativeBridge.connectBluetooth(deviceId);

  Future<bool> disconnectBluetooth(String deviceId) =>
      nativeBridge.disconnectBluetooth(deviceId);

  Future<String?> readBluetoothCharacteristic(
          String deviceId, String serviceUuid, String charUuid) =>
      nativeBridge.readBluetoothCharacteristic(deviceId, serviceUuid, charUuid);

  Future<bool> writeBluetoothCharacteristic(
          String deviceId, String serviceUuid, String charUuid, String value) =>
      nativeBridge.writeBluetoothCharacteristic(
          deviceId, serviceUuid, charUuid, value);

  Future<Map<String, dynamic>?> getWifiInfo() => nativeBridge.getWifiInfo();

  Future<Map<String, dynamic>> pingHost(String host, {int timeoutMs = 3000}) =>
      nativeBridge.pingHost(host, timeoutMs: timeoutMs);
}
