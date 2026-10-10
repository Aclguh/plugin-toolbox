import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:plugin_toolbox/src/plugin_host/plugin_native_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late MethodChannel customChannel;
  final List<MethodCall> calls = [];

  setUp(() async {
    calls.clear();
    tempDir = await Directory.systemTemp.createTemp('bridge_test_');

    customChannel = const MethodChannel('test.channel/bridge');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(customChannel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'shareText':
        case 'shareFile':
        case 'saveToGallery':
        case 'exportFile':
        case 'openUrl':
        case 'setTorch':
          return true;
        case 'scanBarcode':
          return 'mock_barcode_123';
        case 'decodeBarcodeFromImage':
          return 'mock_decoded_qrcode';
        case 'startSensor':
        case 'stopSensor':
          return true;
        case 'getSensorData':
          return {'x': 1.0, 'y': 2.0, 'z': 3.0};
        case 'imageInfo':
          return {'width': 100, 'height': 200, 'format': 'image/png'};
        case 'cropImage':
        case 'compressImage':
        case 'convertImage':
        case 'stripExifImage':
          return true;
        case 'showNotification':
          return 101;
        case 'scheduleNotification':
          return 102;
        case 'cancelNotification':
        case 'cancelAllNotifications':
          return true;
        case 'playTone':
        case 'playAudio':
        case 'stopAudio':
          return true;
        case 'startRecording':
          return true;
        case 'stopRecording':
          return {'path': 'mock_recording.m4a', 'durationMs': 1200};
        case 'getRecordingAmplitude':
          return {'max': 65.5};
        case 'getBatteryLevel':
          return 85;
        case 'getNetworkStatus':
          return 'wifi';
        case 'setKeepScreenOn':
        case 'setBrightness':
        case 'resetBrightness':
          return true;
        case 'getBrightness':
          return 0.8;
        case 'isLocationAvailable':
          return true;
        case 'getCurrentPosition':
          return {'latitude': 31.23, 'longitude': 121.47, 'accuracy': 5.0};
        case 'isNfcAvailable':
          return true;
        case 'readNdef':
          return {'id': 'nfc_01', 'text': 'NDEF Payload'};
        case 'writeNdef':
          return true;
        case 'isBiometricsAvailable':
        case 'authenticateBiometrics':
          return true;
        case 'isBluetoothAvailable':
        case 'startBluetoothScan':
        case 'stopBluetoothScan':
        case 'connectBluetooth':
        case 'disconnectBluetooth':
          return true;
        case 'readBluetoothCharacteristic':
          return '48656c6c6f';
        case 'writeBluetoothCharacteristic':
          return true;
        case 'speak':
        case 'stopSpeaking':
          return true;
        case 'recognizeText':
          return {'text': 'Mock OCR Result', 'blocks': <dynamic>[]};
        case 'getInitialShare':
          return {'type': 'text', 'content': 'Initial shared content'};
        case 'hasPermission':
        case 'requestPermission':
          return true;
        case 'isAiAvailable':
          return true;
        case 'aiChat':
          return {'ok': true, 'response': 'AI generated answer'};
        default:
          return null;
      }
    });
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('PluginNativeBridge 单元测试与原生通道交互', () {
    test('支持自定义通道注入与基础状态初始值', () {
      final bridge = PluginNativeBridge(
        pluginRootDir: tempDir,
        nativeChannel: customChannel,
        logger: Logger(),
      );

      expect(bridge.isTorchOn, isFalse);
      expect(bridge.isScreenKeepOn, isFalse);
      expect(bridge.isBrightnessModified, isFalse);
    });

    test('系统功能: shareText, openUrl, setTorch, shareFile, saveToGallery, exportFile', () async {
      final bridge = PluginNativeBridge(
        pluginRootDir: tempDir,
        nativeChannel: customChannel,
      );

      await bridge.shareText('hello', subject: 'greeting');
      expect(calls.any((c) => c.method == 'shareText'), isTrue);

      final openResult = await bridge.openUrl('https://example.com');
      expect(openResult, isTrue);

      final torchResult = await bridge.setTorch(true);
      expect(torchResult, isTrue);
      expect(bridge.isTorchOn, isTrue);

      final shareFileResult = await bridge.shareFile('/path/to/file.png');
      expect(shareFileResult, isTrue);

      final galleryResult = await bridge.saveToGallery('/path/to/img.jpg');
      expect(galleryResult, isTrue);

      final exportResult = await bridge.exportFile('/path/to/doc.pdf');
      expect(exportResult, isTrue);
    });

    test('传感器模块: startSensor, stopSensor, getSensorData 与内存缓存', () async {
      final bridge = PluginNativeBridge(
        pluginRootDir: tempDir,
        nativeChannel: customChannel,
      );

      final startOk = await bridge.startSensor('accelerometer');
      expect(startOk, isTrue);

      final data = await bridge.getSensorData('accelerometer');
      expect(data, isNotNull);
      expect(data!['x'], 1.0);

      final stopOk = await bridge.stopSensor('accelerometer');
      expect(stopOk, isTrue);
    });

    test('图像处理与信息获取: imageInfo, cropImage, compressImage, convertImage, stripExifImage', () async {
      final bridge = PluginNativeBridge(
        pluginRootDir: tempDir,
        nativeChannel: customChannel,
      );

      final info = await bridge.imageInfo('/img.png');
      expect(info!['width'], 100);
      expect(info['format'], 'image/png');

      expect(await bridge.cropImage('src.png', 'dst.png', x: 0, y: 0, width: 50, height: 50), isTrue);
      expect(await bridge.compressImage('src.png', 'dst.png', quality: 80), isTrue);
      expect(await bridge.convertImage('src.png', 'dst.webp', format: 'webp'), isTrue);
      expect(await bridge.stripExifImage('src.png', 'dst.png'), isTrue);
    });

    test('音频播放与分贝录制: playTone, playAudio, stopAudio, startAudioRecording, stopAudioRecording, getAudioDecibel', () async {
      final bridge = PluginNativeBridge(
        pluginRootDir: tempDir,
        nativeChannel: customChannel,
      );

      expect(await bridge.playTone(440.0, 500), isTrue);
      expect(await bridge.playAudio('track.mp3'), isTrue);
      expect(await bridge.stopAudio(), isTrue);

      expect(await bridge.startAudioRecording('record.m4a'), isTrue);
      expect(await bridge.getAudioDecibel(), 65.5);
      final recResult = await bridge.stopAudioRecording();
      expect(recResult!['path'], 'mock_recording.m4a');
      expect(recResult['durationMs'], 1200);
    });

    test('设备硬件与感知状态: battery, network, screen, brightness', () async {
      final bridge = PluginNativeBridge(
        pluginRootDir: tempDir,
        nativeChannel: customChannel,
      );

      expect(await bridge.getBatteryLevel(), 85);
      expect(await bridge.fetchNetworkType(), 'wifi');

      expect(await bridge.setKeepScreenOn(true), isTrue);
      expect(bridge.isScreenKeepOn, isTrue);

      expect(await bridge.setBrightness(0.8), isTrue);
      expect(bridge.isBrightnessModified, isTrue);
      expect(await bridge.getBrightness(), 0.8);

      expect(await bridge.resetBrightness(), isTrue);
      expect(bridge.isBrightnessModified, isFalse);
    });

    test('扩展能力: biometrics, location, nfc, bluetooth, tts, ocr, barcode, permissions, ai', () async {
      final bridge = PluginNativeBridge(
        pluginRootDir: tempDir,
        nativeChannel: customChannel,
      );

      expect(await bridge.isBiometricsAvailable(), isTrue);
      final auth = await bridge.authenticateBiometrics(reason: '测试验证');
      expect(auth['success'], isTrue);

      expect(await bridge.isLocationAvailable(), isTrue);
      final loc = await bridge.getCurrentPosition();
      expect(loc!['latitude'], 31.23);

      expect(await bridge.isNfcAvailable(), isTrue);
      final tag = await bridge.readNdef();
      expect(tag!['id'], 'nfc_01');
      expect(await bridge.writeNdef([{'type': 'T', 'payload': 'text'}]), isTrue);

      expect(await bridge.isBluetoothAvailable(), isTrue);
      expect(await bridge.startBluetoothScan((device) {}), isTrue);
      expect(await bridge.stopBluetoothScan(), isTrue);
      expect(await bridge.connectBluetooth('mac_addr'), isTrue);
      expect(await bridge.readBluetoothCharacteristic('mac', 'srv', 'chr'), '48656c6c6f');
      expect(await bridge.writeBluetoothCharacteristic('mac', 'srv', 'chr', 'hex'), isTrue);
      expect(await bridge.disconnectBluetooth('mac_addr'), isTrue);

      expect(await bridge.speakText('Hello'), isTrue);
      expect(await bridge.stopSpeaking(), isTrue);

      final barcode = await bridge.scanBarcode();
      expect(barcode, 'mock_barcode_123');
      final decoded = await bridge.decodeBarcodeFromImage('/path/to/code.png');
      expect(decoded, 'mock_decoded_qrcode');

      final testImg = File('${tempDir.path}/img.png');
      testImg.writeAsStringSync('dummy_image_data');
      final ocr = await bridge.recognizeText('img.png');
      expect(ocr!['text'], 'Mock OCR Result');

      final initShare = await bridge.getInitialShare();
      expect(initShare!['type'], 'text');

      expect(await bridge.hasSystemPermission('location'), isTrue);
      expect(await bridge.requestSystemPermission('location'), isTrue);

      expect(await bridge.isAiAvailable(), isTrue);
      final aiRes = await bridge.aiChat(messages: [{'role': 'user', 'content': 'hi'}]);
      expect(aiRes['ok'], isTrue);
    });

    test('通知发送与取消', () async {
      final bridge = PluginNativeBridge(
        pluginRootDir: tempDir,
        nativeChannel: customChannel,
      );

      expect(await bridge.showNotification(title: 'Title', body: 'Body'), 101);
      expect(await bridge.scheduleNotification(title: 'Sched', body: 'SchedBody', delaySeconds: 10), 102);
      expect(await bridge.cancelNotification(101), isTrue);
      expect(await bridge.cancelAllNotifications(), isTrue);
    });

    test('异常容错与 Logger 捕获: 原生抛出 PlatformException 时优雅降级', () async {
      const errChannel = MethodChannel('test.channel/error_bridge');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(errChannel, (call) async {
        throw PlatformException(
          code: 'UNAVAILABLE',
          message: 'Hardware feature is not available',
        );
      });

      final bridge = PluginNativeBridge(
        pluginRootDir: tempDir,
        nativeChannel: errChannel,
        logger: Logger(),
      );

      // 各方法优雅降级为默认安全值而不抛出未捕获异常
      expect(await bridge.openUrl('https://example.com'), isFalse);
      expect(await bridge.shareFile('/file'), isFalse);
      expect(await bridge.startSensor('accelerometer'), isFalse);
      expect(await bridge.getSensorData('accelerometer'), isNull);
      expect(await bridge.scanBarcode(), isNull);
      expect(await bridge.imageInfo('/img'), isNull);
      expect(await bridge.getBatteryLevel(), 100);
      expect(await bridge.fetchNetworkType(), 'unknown');
      expect(await bridge.getCurrentPosition(), isNull);
      final auth = await bridge.authenticateBiometrics();
      expect(auth['success'], isFalse);
      expect(await bridge.hasSystemPermission('camera'), isFalse);
      expect(await bridge.requestSystemPermission('camera'), isFalse);
    });

    test('dispose 资源释放正常重置设备状态', () async {
      final bridge = PluginNativeBridge(
        pluginRootDir: tempDir,
        nativeChannel: customChannel,
      );

      await bridge.setTorch(true);
      await bridge.setKeepScreenOn(true);
      await bridge.setBrightness(0.5);

      expect(bridge.isTorchOn, isTrue);
      expect(bridge.isScreenKeepOn, isTrue);
      expect(bridge.isBrightnessModified, isTrue);

      bridge.dispose();

      expect(bridge.isTorchOn, isFalse);
      expect(bridge.isScreenKeepOn, isFalse);
      expect(bridge.isBrightnessModified, isFalse);
      expect(calls.any((c) => c.method == 'stopSensor'), isTrue);
      expect(calls.any((c) => c.method == 'stopAudio'), isTrue);
    });
  });
}
