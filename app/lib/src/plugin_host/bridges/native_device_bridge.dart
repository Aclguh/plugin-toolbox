import 'bridge_base.dart';

/// 设备级原生能力领域扩展 (手电筒、屏幕显示、电池与系统分享)
mixin NativeDeviceBridge on NativeBridgeBase {
  bool _torchOn = false;
  bool _screenKeepOn = false;
  bool _brightnessModified = false;

  bool get isTorchOn => _torchOn;
  bool get isScreenKeepOn => _screenKeepOn;
  bool get isBrightnessModified => _brightnessModified;

  void disposeDeviceBridge() {
    if (_torchOn) {
      _torchOn = false;
      setTorch(false);
    }
    if (_screenKeepOn) {
      _screenKeepOn = false;
      setKeepScreenOn(false);
    }
    if (_brightnessModified) {
      _brightnessModified = false;
      resetBrightness();
    }
  }

  Future<void> shareText(String text, {String? subject}) async {
    try {
      await nativeChannel.invokeMethod('shareText', {
        'text': text,
        'subject': subject,
      });
    } catch (e, st) {
      logError('shareText', e, st);
    }
  }

  Future<bool> openUrl(String url) async {
    final uri = Uri.tryParse(url.trim());
    final scheme = uri?.scheme.toLowerCase() ?? '';
    if (uri == null || (scheme != 'http' && scheme != 'https')) {
      logger?.w('PluginNativeBridge: openUrl 拒绝非 http(s) 链接: $url');
      return false;
    }
    return invoke<bool>('openUrl', false, {'url': url});
  }

  Future<bool> setTorch(bool enabled) async {
    _torchOn = enabled;
    try {
      final res = await nativeChannel
          .invokeMethod<bool>('setTorch', {'enabled': enabled});
      return res ?? true;
    } catch (e, st) {
      logError('setTorch', e, st);
      _torchOn = !enabled;
      return false;
    }
  }

  Future<bool> shareFile(
    String filePath, {
    String? mimeType,
    String? subject,
  }) async {
    final resolved = resolveSandboxPath(filePath, 'shareFile');
    if (resolved == null) return false;
    return invoke<bool>('shareFile', false, {
      'path': resolved,
      'mimeType': mimeType,
      'subject': subject,
    });
  }

  Future<bool> setKeepScreenOn(bool keepOn) async {
    _screenKeepOn = keepOn;
    return invoke<bool>('setKeepScreenOn', false, {'keepOn': keepOn});
  }

  Future<double> getBrightness() => invoke<double>('getBrightness', 1.0);

  Future<bool> setBrightness(double brightness) async {
    final clamped = brightness.clamp(0.0, 1.0);
    _brightnessModified = true;
    return invoke<bool>('setBrightness', false, {'brightness': clamped});
  }

  Future<bool> resetBrightness() async {
    _brightnessModified = false;
    return invoke<bool>('resetBrightness', false);
  }

  Future<int> getBatteryLevel() => invoke<int>('getBatteryLevel', -1);

  Future<String> fetchNetworkType() =>
      invoke<String>('getNetworkStatus', 'unknown');

  Future<Map<String, dynamic>?> getInitialShare() =>
      invokeMap('getInitialShare');
}
