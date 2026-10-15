import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'bridge_base.dart';

/// 硬件连接、外设与系统底层能力领域扩展 (蓝牙 BLE, NFC, 生物认证, 定位)
mixin NativeHardwareBridge on NativeBridgeBase {
  void Function(Map<String, dynamic> device)? _onBluetoothDeviceFound;
  bool _nativeCallbackRegistered = false;

  void ensureNativeCallbackRegistered() {
    if (_nativeCallbackRegistered) return;
    _nativeCallbackRegistered = true;
    nativeChannel.setMethodCallHandler(handleNativeCallback);
  }

  @visibleForTesting
  Future<dynamic> handleNativeCallback(MethodCall call) async {
    if (call.method == 'onBluetoothDeviceFound') {
      final args = call.arguments;
      if (args is Map) {
        final device = Map<String, dynamic>.from(args);
        _onBluetoothDeviceFound?.call(device);
      }
    }
    return null;
  }

  Future<bool> isBiometricsAvailable() =>
      invoke<bool>('isBiometricsAvailable', false);

  Future<Map<String, dynamic>> authenticateBiometrics({String? reason}) async {
    try {
      final res = await nativeChannel.invokeMethod<bool>(
        'authenticateBiometrics',
        {'reason': reason},
      );
      return {'success': res ?? false};
    } catch (e, st) {
      logError('authenticateBiometrics', e, st);
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<bool> authenticateBiometric({String? localizedReason}) =>
      invoke<bool>('authenticateBiometric', false, {
        if (localizedReason != null) 'localizedReason': localizedReason,
      });

  Future<bool> isLocationAvailable() =>
      invoke<bool>('isLocationAvailable', false);

  Future<Map<String, dynamic>?> getCurrentPosition() =>
      invokeMap('getCurrentPosition');

  Future<bool> hasSystemPermission(String permission) =>
      invoke<bool>('hasPermission', false, {'permission': permission});

  Future<bool> requestSystemPermission(String permission) =>
      invoke<bool>('requestPermission', false, {'permission': permission});

  Future<bool> isAiAvailable() => invoke<bool>('isAiAvailable', false);

  Future<Map<String, dynamic>> aiChat({
    required List<Map<String, dynamic>> messages,
    String? model,
    double? temperature,
  }) async {
    final res = await invokeMap('aiChat', {
      'messages': messages,
      'model': model,
      'temperature': temperature,
    });
    return res ?? {'ok': false, 'error': 'AI 网关未配置或服务不可用'};
  }

  Stream<String> aiStreamChat({
    required List<Map<String, dynamic>> messages,
    String? model,
    double? temperature,
  }) {
    return Stream.error(
        UnimplementedError('aiStreamChat 流式对话尚未实现，请降级使用 aiChat'));
  }

  Future<Map<String, dynamic>> getCapabilities() async {
    final nativeCaps = await invokeMap('getCapabilities');
    final baseCapabilities = <String, dynamic>{
      'platform': Platform.operatingSystem,
      'torch': true,
      'haptic': true,
      'clipboard': true,
      'biometrics': true,
      'camera': Platform.isAndroid || Platform.isIOS,
      'sensors': Platform.isAndroid || Platform.isIOS,
      'nfc': Platform.isAndroid,
      'bluetooth': Platform.isAndroid || Platform.isIOS,
      'ocr': Platform.isAndroid || Platform.isIOS,
      'ai': false,
      'filePicker': true,
    };
    if (nativeCaps != null) {
      baseCapabilities.addAll(nativeCaps);
    }
    return baseCapabilities;
  }

  Future<bool> isNfcAvailable() => invoke<bool>('isNfcAvailable', false);

  Future<Map<String, dynamic>?> readNdef() => invokeMap('readNdef');

  Future<bool> writeNdef(List<Map<String, dynamic>> records) =>
      invoke<bool>('writeNdef', false, {'records': records});

  Future<bool> isBluetoothAvailable() =>
      invoke<bool>('isBluetoothAvailable', false);

  Future<bool> startBluetoothScan(
    void Function(Map<String, dynamic> device) onDeviceFound,
  ) async {
    _onBluetoothDeviceFound = onDeviceFound;
    ensureNativeCallbackRegistered();
    return invoke<bool>('startBluetoothScan', false);
  }

  Future<bool> stopBluetoothScan() async {
    _onBluetoothDeviceFound = null;
    return invoke<bool>('stopBluetoothScan', false);
  }

  Future<bool> connectBluetooth(String deviceId) =>
      invoke<bool>('connectBluetooth', false, {'deviceId': deviceId});

  Future<bool> disconnectBluetooth(String deviceId) =>
      invoke<bool>('disconnectBluetooth', false, {'deviceId': deviceId});

  Future<String?> readBluetoothCharacteristic(
    String deviceId,
    String serviceUuid,
    String charUuid,
  ) async {
    try {
      return await nativeChannel
          .invokeMethod<String>('readBluetoothCharacteristic', {
        'deviceId': deviceId,
        'serviceUuid': serviceUuid,
        'charUuid': charUuid,
      });
    } catch (e, st) {
      logError('readBluetoothCharacteristic', e, st);
      return null;
    }
  }

  Future<bool> writeBluetoothCharacteristic(
    String deviceId,
    String serviceUuid,
    String charUuid,
    String value,
  ) =>
      invoke<bool>('writeBluetoothCharacteristic', false, {
        'deviceId': deviceId,
        'serviceUuid': serviceUuid,
        'charUuid': charUuid,
        'value': value,
      });

  Future<Map<String, dynamic>?> getWifiInfo() => invokeMap('getWifiInfo');

  Future<Map<String, dynamic>> pingHost(
    String host, {
    int timeoutMs = 3000,
  }) async {
    final res = await invokeMap('pingHost', {
      'host': host,
      'timeoutMs': timeoutMs,
    });
    return res ?? {'ok': false, 'error': 'not_supported'};
  }
}
