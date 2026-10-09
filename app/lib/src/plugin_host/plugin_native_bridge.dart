import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

/// 动态插件与宿主 Android 原生及系统能力调度的专用桥接层
class PluginNativeBridge {
  static const MethodChannel _nativeChannel =
      MethodChannel('com.plugintoolbox/host_native');

  final Directory pluginRootDir;
  final Map<String, Map<String, dynamic>> _sensorCache = {};

  bool _torchOn = false;
  bool _screenKeepOn = false;
  bool _brightnessModified = false;

  PluginNativeBridge({required this.pluginRootDir});

  bool get isTorchOn => _torchOn;
  bool get isScreenKeepOn => _screenKeepOn;
  bool get isBrightnessModified => _brightnessModified;

  void dispose() {
    if (_torchOn) {
      setTorch(false);
    }
    if (_screenKeepOn) {
      setKeepScreenOn(false);
    }
    if (_brightnessModified) {
      resetBrightness();
    }
    stopSensor('all');
    stopAudio();
  }

  // --- 基础系统调用 ---
  Future<void> shareText(String text, {String? subject}) async {
    try {
      await _nativeChannel.invokeMethod('shareText', {
        'text': text,
        'subject': subject,
      });
    } catch (_) {}
  }

  Future<bool> openUrl(String url) async {
    try {
      final res = await _nativeChannel.invokeMethod<bool>('openUrl', {
        'url': url,
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> setTorch(bool enabled) async {
    _torchOn = enabled;
    try {
      await _nativeChannel.invokeMethod<bool>('setTorch', {'enabled': enabled});
    } catch (_) {}
    return true;
  }

  Future<bool> shareFile(
    String filePath, {
    String? mimeType,
    String? subject,
  }) async {
    try {
      final res = await _nativeChannel.invokeMethod<bool>('shareFile', {
        'path': filePath,
        'mimeType': mimeType,
        'subject': subject,
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> saveToGallery(String filePath) async {
    try {
      final res = await _nativeChannel.invokeMethod<bool>('saveToGallery', {
        'path': filePath,
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> exportFile(String filePath, {String? defaultName}) async {
    try {
      final res = await _nativeChannel.invokeMethod<bool>('exportFile', {
        'path': filePath,
        'defaultName': defaultName,
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  // --- 文件与图片选择与沙箱写入 ---
  Future<String?> pickFile({List<String>? allowedExtensions}) async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: (allowedExtensions != null && allowedExtensions.isNotEmpty)
            ? FileType.custom
            : FileType.any,
        allowedExtensions: allowedExtensions,
      );
      if (res == null || res.files.isEmpty) return null;
      final file = res.files.first;
      final srcPath = file.path;
      if (srcPath == null) return null;

      final fileName = file.name;
      final destDir = Directory('${pluginRootDir.path}/data');
      if (!destDir.existsSync()) {
        destDir.createSync(recursive: true);
      }
      final destFile = File('${destDir.path}/$fileName');
      await File(srcPath).copy(destFile.path);
      return 'data/$fileName';
    } catch (_) {
      return null;
    }
  }

  Future<String?> pickImage() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.image,
      );
      if (res == null || res.files.isEmpty) return null;
      final file = res.files.first;
      final srcPath = file.path;
      if (srcPath == null) return null;

      final fileName = file.name;
      final destDir = Directory('${pluginRootDir.path}/data');
      if (!destDir.existsSync()) {
        destDir.createSync(recursive: true);
      }
      final destFile = File('${destDir.path}/$fileName');
      await File(srcPath).copy(destFile.path);
      return 'data/$fileName';
    } catch (_) {
      return null;
    }
  }

  // --- 条码识别 ---
  Future<String?> scanBarcode({String? prompt}) async {
    try {
      final res = await _nativeChannel.invokeMethod<String>('scanBarcode', {
        'prompt': prompt,
      });
      return res;
    } catch (_) {
      return null;
    }
  }

  Future<String?> decodeBarcodeFromImage(String filePath) async {
    try {
      final res = await _nativeChannel.invokeMethod<String>(
        'decodeBarcodeFromImage',
        {'path': filePath},
      );
      return res;
    } catch (_) {
      return null;
    }
  }

  // --- 传感器交互 ---
  Future<bool> startSensor(String type) async {
    try {
      final res = await _nativeChannel.invokeMethod<bool>('startSensor', {
        'type': type,
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> stopSensor(String type) async {
    try {
      final res = await _nativeChannel.invokeMethod<bool>('stopSensor', {
        'type': type,
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>?> getSensorData(String type) async {
    try {
      final res = await _nativeChannel.invokeMapMethod<String, dynamic>(
        'getSensorData',
        {'type': type},
      );
      if (res != null) {
        _sensorCache[type] = res;
      }
      return res ?? _sensorCache[type];
    } catch (_) {
      return _sensorCache[type];
    }
  }

  // --- 媒体图像处理 ---
  Future<Map<String, dynamic>?> imageInfo(String filePath) async {
    try {
      final res = await _nativeChannel.invokeMapMethod<String, dynamic>(
        'imageInfo',
        {'path': filePath},
      );
      return res;
    } catch (_) {
      return null;
    }
  }

  Future<bool> compressImage(
    String srcPath,
    String destPath, {
    int quality = 80,
  }) async {
    try {
      final res = await _nativeChannel.invokeMethod<bool>('compressImage', {
        'src': srcPath,
        'dest': destPath,
        'quality': quality,
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> cropImage(
    String srcPath,
    String destPath, {
    required int x,
    required int y,
    required int width,
    required int height,
  }) async {
    try {
      final res = await _nativeChannel.invokeMethod<bool>('cropImage', {
        'src': srcPath,
        'dest': destPath,
        'x': x,
        'y': y,
        'width': width,
        'height': height,
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> convertImage(
    String srcPath,
    String destPath, {
    required String format,
  }) async {
    try {
      final res = await _nativeChannel.invokeMethod<bool>('convertImage', {
        'src': srcPath,
        'dest': destPath,
        'format': format,
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> stripExifImage(String srcPath, String destPath) async {
    try {
      final res = await _nativeChannel.invokeMethod<bool>('stripExifImage', {
        'src': srcPath,
        'dest': destPath,
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  // --- 系统通知 ---
  Future<int> showNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    try {
      final res = await _nativeChannel.invokeMethod<int>('showNotification', {
        'title': title,
        'body': body,
        'payload': payload,
      });
      return res ?? -1;
    } catch (_) {
      return -1;
    }
  }

  Future<int> scheduleNotification({
    required String title,
    required String body,
    required int delaySeconds,
    String? payload,
  }) async {
    try {
      final res = await _nativeChannel.invokeMethod<int>('scheduleNotification', {
        'title': title,
        'body': body,
        'delaySeconds': delaySeconds,
        'payload': payload,
      });
      return res ?? -1;
    } catch (_) {
      return -1;
    }
  }

  Future<bool> cancelNotification(int id) async {
    try {
      final res = await _nativeChannel.invokeMethod<bool>('cancelNotification', {
        'id': id,
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> cancelAllNotifications() async {
    try {
      final res =
          await _nativeChannel.invokeMethod<bool>('cancelAllNotifications');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  // --- 音频播放与合成 ---
  Future<bool> playAudio(String filePath) async {
    try {
      final res = await _nativeChannel.invokeMethod<bool>('playAudio', {
        'path': filePath,
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> stopAudio() async {
    try {
      final res = await _nativeChannel.invokeMethod<bool>('stopAudio');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> playTone(double frequencyHz, int durationMs) async {
    try {
      final res = await _nativeChannel.invokeMethod<bool>('playTone', {
        'frequency': frequencyHz,
        'durationMs': durationMs,
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  // --- 录音与分贝感知 ---
  Future<bool> startAudioRecording(String destPath) async {
    try {
      final res = await _nativeChannel.invokeMethod<bool>('startRecording', {
        'path': destPath,
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>?> stopAudioRecording() async {
    try {
      return await _nativeChannel.invokeMapMethod<String, dynamic>('stopRecording');
    } catch (_) {
      return null;
    }
  }

  Future<double> getAudioDecibel() async {
    try {
      final res = await _nativeChannel.invokeMapMethod<String, dynamic>(
        'getRecordingAmplitude',
      );
      if (res != null && res['max'] != null) {
        return (res['max'] as num).toDouble();
      }
      return 0.0;
    } catch (_) {
      return 0.0;
    }
  }

  // --- 语音朗读 (TTS) ---
  Future<bool> speakText(
    String text, {
    String? language,
    double? pitch,
    double? rate,
  }) async {
    try {
      final res = await _nativeChannel.invokeMethod<bool>('speak', {
        'text': text,
        'language': language,
        'rate': rate ?? 1.0,
        'pitch': pitch ?? 1.0,
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> stopSpeaking() async {
    try {
      final res = await _nativeChannel.invokeMethod<bool>('stopSpeaking');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  // --- 屏幕控制与常亮 ---
  Future<bool> setKeepScreenOn(bool enabled) async {
    _screenKeepOn = enabled;
    try {
      final res = await _nativeChannel.invokeMethod<bool>(
        'setKeepScreenOn',
        {'enabled': enabled},
      );
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> setBrightness(double brightness) async {
    _brightnessModified = true;
    try {
      final res = await _nativeChannel.invokeMethod<bool>(
        'setBrightness',
        {'brightness': brightness},
      );
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<double> getBrightness() async {
    try {
      final res = await _nativeChannel.invokeMethod<double>('getBrightness');
      return res ?? 1.0;
    } catch (_) {
      return 1.0;
    }
  }

  Future<bool> resetBrightness() async {
    _brightnessModified = false;
    try {
      final res = await _nativeChannel.invokeMethod<bool>('resetBrightness');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  // --- 电池、网络状态感知 ---
  Future<int> getBatteryLevel() async {
    try {
      final res = await _nativeChannel.invokeMethod<int>('getBatteryLevel');
      return res ?? 100;
    } catch (_) {
      return 100;
    }
  }

  Future<String> fetchNetworkType() async {
    try {
      final res =
          await _nativeChannel.invokeMethod<String>('getNetworkStatus');
      return res ?? 'unknown';
    } catch (_) {
      return 'unknown';
    }
  }

  // --- 系统分享接收 ---
  Future<Map<String, dynamic>?> getInitialShare() async {
    try {
      return await _nativeChannel.invokeMapMethod<String, dynamic>(
        'getInitialShare',
      );
    } catch (_) {
      return null;
    }
  }

  // --- 生物认证 ---
  Future<bool> isBiometricsAvailable() async {
    return true;
  }

  Future<Map<String, dynamic>> authenticateBiometrics({String? reason}) async {
    try {
      final res = await _nativeChannel.invokeMethod<bool>(
        'authenticateBiometrics',
        {'reason': reason},
      );
      return {'success': res ?? false};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  // --- 地理位置 ---
  Future<bool> isLocationAvailable() async {
    try {
      final res =
          await _nativeChannel.invokeMethod<bool>('isLocationAvailable');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>?> getCurrentPosition() async {
    try {
      return await _nativeChannel.invokeMapMethod<String, dynamic>(
        'getCurrentPosition',
      );
    } catch (_) {
      return null;
    }
  }

  // --- NFC ---
  Future<bool> isNfcAvailable() async {
    try {
      final res = await _nativeChannel.invokeMethod<bool>('isNfcAvailable');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>?> readNdef() async {
    try {
      return await _nativeChannel.invokeMapMethod<String, dynamic>('readNdef');
    } catch (_) {
      return null;
    }
  }

  Future<bool> writeNdef(List<Map<String, dynamic>> records) async {
    try {
      final res = await _nativeChannel.invokeMethod<bool>('writeNdef', {
        'records': records,
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  // --- 蓝牙低功耗 (BLE) ---
  Future<bool> isBluetoothAvailable() async {
    try {
      final res =
          await _nativeChannel.invokeMethod<bool>('isBluetoothAvailable');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> startBluetoothScan(
      void Function(Map<String, dynamic> device) onDeviceFound) async {
    try {
      final res =
          await _nativeChannel.invokeMethod<bool>('startBluetoothScan');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> stopBluetoothScan() async {
    try {
      final res =
          await _nativeChannel.invokeMethod<bool>('stopBluetoothScan');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> connectBluetooth(String deviceId) async {
    try {
      final res = await _nativeChannel.invokeMethod<bool>('connectBluetooth', {
        'deviceId': deviceId,
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> disconnectBluetooth(String deviceId) async {
    try {
      final res = await _nativeChannel.invokeMethod<bool>(
        'disconnectBluetooth',
        {'deviceId': deviceId},
      );
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<String?> readBluetoothCharacteristic(
    String deviceId,
    String serviceUuid,
    String charUuid,
  ) async {
    try {
      return await _nativeChannel.invokeMethod<String>(
        'readBluetoothCharacteristic',
        {
          'deviceId': deviceId,
          'serviceUuid': serviceUuid,
          'charUuid': charUuid,
        },
      );
    } catch (_) {
      return null;
    }
  }

  Future<bool> writeBluetoothCharacteristic(
    String deviceId,
    String serviceUuid,
    String charUuid,
    String value,
  ) async {
    try {
      final res = await _nativeChannel.invokeMethod<bool>(
        'writeBluetoothCharacteristic',
        {
          'deviceId': deviceId,
          'serviceUuid': serviceUuid,
          'charUuid': charUuid,
          'value': value,
        },
      );
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  // --- 离线 OCR ---
  Future<Map<String, dynamic>?> recognizeText(String filePath) async {
    try {
      final file = File('${pluginRootDir.path}/$filePath');
      if (!file.existsSync()) return null;
      return await _nativeChannel.invokeMapMethod<String, dynamic>('recognizeText', {
        'path': file.path,
      });
    } catch (_) {
      return null;
    }
  }

  // --- 宿主统一 AI 网关 ---
  Future<bool> isAiAvailable() async {
    try {
      final res = await _nativeChannel.invokeMethod<bool>('isAiAvailable');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> aiChat({
    required List<Map<String, dynamic>> messages,
    String? model,
    double? temperature,
  }) async {
    try {
      final res = await _nativeChannel.invokeMapMethod<String, dynamic>('aiChat', {
        'messages': messages,
        'model': model,
        'temperature': temperature,
      });
      return res ?? {'ok': false, 'error': 'AI 网关未配置或服务不可用'};
    } catch (_) {
      return {'ok': false, 'error': 'AI 网关未配置或服务不可用'};
    }
  }

  Stream<String> aiStreamChat({
    required List<Map<String, dynamic>> messages,
    String? model,
    double? temperature,
  }) {
    return const Stream.empty();
  }
}
