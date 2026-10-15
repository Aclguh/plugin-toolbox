import 'plugin_native_bridge.dart';

/// LuaHostDelegate 的媒体能力域方法集：文件分享/导出、图像处理、
/// 音频播放、录音分贝、TTS 与离线 OCR。
///
/// 全部为桥接层的同构转发，路径安全校验统一收口在
/// [PluginNativeBridge] 内部；从宿主页拆出以便按能力域独立演进。
mixin PluginHostMediaDelegate {
  PluginNativeBridge get nativeBridge;

  Future<bool> shareFile(String filePath,
          {String? mimeType, String? subject}) =>
      nativeBridge.shareFile(filePath, mimeType: mimeType, subject: subject);

  Future<bool> saveToGallery(String filePath) =>
      nativeBridge.saveToGallery(filePath);

  Future<bool> exportFile(String filePath, {String? defaultName}) =>
      nativeBridge.exportFile(filePath, defaultName: defaultName);

  Future<String?> pickFile({List<String>? allowedExtensions}) =>
      nativeBridge.pickFile(allowedExtensions: allowedExtensions);

  Future<String?> pickImage() => nativeBridge.pickImage();

  Future<Map<String, dynamic>?> imageInfo(String filePath) =>
      nativeBridge.imageInfo(filePath);

  Future<bool> compressImage(String srcPath, String destPath,
          {int quality = 80}) =>
      nativeBridge.compressImage(srcPath, destPath, quality: quality);

  Future<bool> cropImage(String srcPath, String destPath,
          {required int x,
          required int y,
          required int width,
          required int height}) =>
      nativeBridge.cropImage(srcPath, destPath,
          x: x, y: y, width: width, height: height);

  Future<bool> convertImage(String srcPath, String destPath,
          {required String format}) =>
      nativeBridge.convertImage(srcPath, destPath, format: format);

  Future<bool> stripExifImage(String srcPath, String destPath) =>
      nativeBridge.stripExifImage(srcPath, destPath);

  Future<bool> playAudio(String filePath) => nativeBridge.playAudio(filePath);

  Future<bool> stopAudio() => nativeBridge.stopAudio();

  Future<bool> playTone(double frequencyHz, int durationMs) =>
      nativeBridge.playTone(frequencyHz, durationMs);

  Future<bool> startAudioRecording(String destPath) =>
      nativeBridge.startAudioRecording(destPath);

  Future<Map<String, dynamic>?> stopAudioRecording() =>
      nativeBridge.stopAudioRecording();

  Future<double> getAudioDecibel() => nativeBridge.getAudioDecibel();

  Future<bool> speakText(String text,
          {String? language, double? pitch, double? rate}) =>
      nativeBridge.speakText(text,
          language: language, pitch: pitch, rate: rate);

  Future<bool> stopSpeaking() => nativeBridge.stopSpeaking();

  Future<Map<String, dynamic>?> recognizeText(String filePath) =>
      nativeBridge.recognizeText(filePath);

  Future<String?> takePhoto({
    String? destPath,
    int quality = 90,
    String lensDirection = 'back',
  }) =>
      nativeBridge.takePhoto(
        destPath: destPath,
        quality: quality,
        lensDirection: lensDirection,
      );

  Future<bool> captureScreen({
    required String destPath,
    String? targetRef,
  }) =>
      nativeBridge.captureScreen(
        destPath: destPath,
        targetRef: targetRef,
      );
}
