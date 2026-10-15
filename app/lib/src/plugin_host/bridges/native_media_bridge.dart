import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'bridge_base.dart';

/// 多媒体、图像与视觉感知原生能力领域扩展
mixin NativeMediaBridge on NativeBridgeBase {
  Future<bool> playAudio(String filePath) async {
    final resolved = resolveSandboxPath(filePath, 'playAudio');
    if (resolved == null) return false;
    return invoke<bool>('playAudio', false, {'path': resolved});
  }

  Future<bool> stopAudio() => invoke<bool>('stopAudio', false);

  Future<bool> playTone(double frequencyHz, int durationMs) =>
      invoke<bool>('playTone', false, {
        'frequency': frequencyHz,
        'durationMs': durationMs,
      });

  Future<bool> startAudioRecording(String destPath) async {
    final resolved = resolveSandboxPath(destPath, 'startAudioRecording');
    if (resolved == null) return false;
    return invoke<bool>('startRecording', false, {'path': resolved});
  }

  Future<Map<String, dynamic>?> stopAudioRecording() =>
      invokeMap('stopRecording');

  Future<double> getAudioDecibel() async {
    try {
      final res =
          await nativeChannel.invokeMethod<dynamic>('getRecordingAmplitude');
      if (res is num) return res.toDouble();
      if (res is Map && res.containsKey('max') && res['max'] is num) {
        return (res['max'] as num).toDouble();
      }
      return 0.0;
    } catch (e, st) {
      logError('getAudioDecibel', e, st);
      return 0.0;
    }
  }

  Future<bool> speakText(
    String text, {
    String? language,
    double? pitch,
    double? rate,
  }) =>
      invoke<bool>('speak', false, {
        'text': text,
        if (language != null) 'language': language,
        if (pitch != null) 'pitch': pitch,
        if (rate != null) 'rate': rate,
      });

  Future<bool> stopSpeaking() => invoke<bool>('stopSpeaking', false);

  Future<String?> pickFile({List<String>? allowedExtensions}) =>
      pickAndCopyIntoSandbox(
        allowedExtensions: allowedExtensions,
        type: FileType.any,
        op: 'pickFile',
      );

  Future<String?> pickImage() => pickAndCopyIntoSandbox(
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
        type: FileType.image,
        op: 'pickImage',
      );

  Future<String?> pickVideo() => pickAndCopyIntoSandbox(
        allowedExtensions: ['mp4', 'mov', 'mkv', 'webm', '3gp'],
        type: FileType.video,
        op: 'pickVideo',
      );

  Future<bool> saveToGallery(String filePath) async {
    final resolved = resolveSandboxPath(filePath, 'saveToGallery');
    if (resolved == null) return false;
    return invoke<bool>('saveToGallery', false, {'path': resolved});
  }

  Future<bool> exportFile(String filePath, {String? defaultName}) async {
    final resolved = resolveSandboxPath(filePath, 'exportFile');
    if (resolved == null) return false;
    return invoke<bool>('exportFile', false, {
      'path': resolved,
      if (defaultName != null) 'defaultName': defaultName,
    });
  }

  Future<String?> takePhoto({
    String? destPath,
    int quality = 90,
    String lensDirection = 'back',
  }) async {
    final effectiveRel =
        destPath ?? 'data/photo_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final resolved = resolveSandboxPath(effectiveRel, 'takePhoto');
    if (resolved == null) return null;

    // 预估单张拍摄照片约为 5MB，预留配额检查
    if (!hasSandboxQuotaFor(5 * 1024 * 1024)) {
      logger?.w('PluginNativeBridge: takePhoto 超出沙箱存储配额');
      return null;
    }

    try {
      final f = File(resolved);
      if (!f.parent.existsSync()) {
        f.parent.createSync(recursive: true);
      }
      return await nativeChannel.invokeMethod<String>('takePhoto', {
        'destPath': resolved,
        'quality': quality,
        'lensDirection': lensDirection,
      });
    } catch (e, st) {
      logError('takePhoto', e, st);
      return null;
    }
  }

  Future<bool> captureScreen({
    required String destPath,
    String? targetRef,
  }) async {
    final resolved = resolveSandboxPath(destPath, 'captureScreen');
    if (resolved == null) return false;

    // 预留截屏 5MB 配额预检
    if (!hasSandboxQuotaFor(5 * 1024 * 1024)) {
      logger?.w('PluginNativeBridge: captureScreen 超出沙箱存储配额');
      return false;
    }

    try {
      final f = File(resolved);
      if (!f.parent.existsSync()) {
        f.parent.createSync(recursive: true);
      }
      final res = await nativeChannel.invokeMethod<bool>('captureScreen', {
        'destPath': resolved,
        'targetRef': targetRef,
      });
      return res ?? false;
    } catch (e, st) {
      logError('captureScreen', e, st);
      return false;
    }
  }

  Future<Map<String, dynamic>?> imageInfo(String filePath) async {
    final resolved = resolveSandboxPath(filePath, 'imageInfo');
    if (resolved == null) return null;
    return invokeMap('imageInfo', {'path': resolved});
  }

  Future<bool> compressImage(
    String srcPath,
    String destPath, {
    int quality = 80,
  }) async {
    final resolvedSrc = resolveSandboxPath(srcPath, 'compressImage.src');
    final resolvedDest = resolveSandboxPath(destPath, 'compressImage.dest');
    if (resolvedSrc == null || resolvedDest == null) return false;
    return invoke<bool>('compressImage', false, {
      'srcPath': resolvedSrc,
      'destPath': resolvedDest,
      'quality': quality,
    });
  }

  Future<bool> cropImage(
    String srcPath,
    String destPath, {
    required int x,
    required int y,
    required int width,
    required int height,
  }) async {
    final resolvedSrc = resolveSandboxPath(srcPath, 'cropImage.src');
    final resolvedDest = resolveSandboxPath(destPath, 'cropImage.dest');
    if (resolvedSrc == null || resolvedDest == null) return false;
    return invoke<bool>('cropImage', false, {
      'srcPath': resolvedSrc,
      'destPath': resolvedDest,
      'x': x,
      'y': y,
      'width': width,
      'height': height,
    });
  }

  Future<bool> convertImage(
    String srcPath,
    String destPath, {
    required String format,
  }) async {
    final resolvedSrc = resolveSandboxPath(srcPath, 'convertImage.src');
    final resolvedDest = resolveSandboxPath(destPath, 'convertImage.dest');
    if (resolvedSrc == null || resolvedDest == null) return false;
    return invoke<bool>('convertImage', false, {
      'srcPath': resolvedSrc,
      'destPath': resolvedDest,
      'format': format,
    });
  }

  Future<bool> stripExifImage(String srcPath, String destPath) async {
    final resolvedSrc = resolveSandboxPath(srcPath, 'stripExifImage.src');
    final resolvedDest = resolveSandboxPath(destPath, 'stripExifImage.dest');
    if (resolvedSrc == null || resolvedDest == null) return false;
    return invoke<bool>('stripExifImage', false, {
      'srcPath': resolvedSrc,
      'destPath': resolvedDest,
    });
  }

  Future<Map<String, dynamic>?> recognizeText(String filePath) async {
    final resolved = resolveSandboxPath(filePath, 'recognizeText');
    if (resolved == null) return null;
    return invokeMap('recognizeText', {'path': resolved});
  }

  Future<String?> scanBarcode({String? prompt}) async {
    try {
      return await nativeChannel.invokeMethod<String>('scanBarcode', {
        if (prompt != null) 'prompt': prompt,
      });
    } catch (e, st) {
      logError('scanBarcode', e, st);
      return null;
    }
  }

  Future<String?> decodeBarcodeFromImage(String filePath) async {
    final resolved = resolveSandboxPath(filePath, 'decodeBarcodeFromImage');
    if (resolved == null) return null;
    try {
      return await nativeChannel
          .invokeMethod<String>('decodeBarcodeFromImage', {'path': resolved});
    } catch (e, st) {
      logError('decodeBarcodeFromImage', e, st);
      return null;
    }
  }
}
