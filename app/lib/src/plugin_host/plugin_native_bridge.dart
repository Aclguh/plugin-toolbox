import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:logger/logger.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';

/// 动态插件与宿主 Android 原生及系统能力调度的专用桥接层
class PluginNativeBridge {
  static const String defaultChannelName = 'com.plugintoolbox/host_native';

  final MethodChannel _nativeChannel;
  final Directory pluginRootDir;
  final Logger? _logger;

  /// 插件沙箱存储配额上限 (MB)，写入型操作（如选取文件入沙箱）前需核对
  final int storageQuotaMb;

  final Map<String, Map<String, dynamic>> _sensorCache = {};

  bool _torchOn = false;
  bool _screenKeepOn = false;
  bool _brightnessModified = false;

  void Function(Map<String, dynamic> device)? _onBluetoothDeviceFound;
  bool _nativeCallbackRegistered = false;

  PluginNativeBridge({
    required this.pluginRootDir,
    this.storageQuotaMb = 50,
    MethodChannel? nativeChannel,
    Logger? logger,
  })  : _nativeChannel =
            nativeChannel ?? const MethodChannel(defaultChannelName),
        _logger = logger;

  bool get isTorchOn => _torchOn;
  bool get isScreenKeepOn => _screenKeepOn;
  bool get isBrightnessModified => _brightnessModified;

  void _logError(String op, Object e, [StackTrace? st]) {
    _logger?.w('PluginNativeBridge: $op 调用失败: $e', error: e, stackTrace: st);
  }

  // --- 统一调用收敛助手 ---

  /// 全部原生方法调用的统一入口：异常与 null 结果一律降级为 [fallback]，
  /// 避免 40 余个方法各自重复同构 try/catch 样板
  Future<T> _invoke<T>(String method, T fallback,
      [Map<String, dynamic>? args]) async {
    try {
      final res = await _nativeChannel.invokeMethod<T>(method, args);
      return res ?? fallback;
    } catch (e, st) {
      _logError(method, e, st);
      return fallback;
    }
  }

  /// Map 返回型原生调用的统一入口：异常降级为 null
  Future<Map<String, dynamic>?> _invokeMap(String method,
      [Map<String, dynamic>? args]) async {
    try {
      return await _nativeChannel.invokeMapMethod<String, dynamic>(
          method, args);
    } catch (e, st) {
      _logError(method, e, st);
      return null;
    }
  }

  /// 将插件侧传入的相对路径解析为沙箱内绝对路径。
  ///
  /// Lua 脚本可传任意字符串（如 `../../etc/passwd` 或绝对路径），
  /// 不经白名单校验直接下发原生即等于开放全设备文件面；
  /// 越界时返回 null 并记录告警，调用方必须拒绝执行。
  String? _resolveSandboxPath(String relativePath, String op) {
    if (!SandboxPath.isSafeSubpath(pluginRootDir.path, relativePath)) {
      _logger?.w('PluginNativeBridge: $op 拒绝越界路径: $relativePath');
      return null;
    }
    return '${pluginRootDir.path}/$relativePath';
  }

  // --- 选取文件入沙箱的清洗工具 ---

  /// 剔除路径分隔符与连续点号：系统文件选择器返回的文件名可被构造为
  /// `../../x` 形态，不净化即拼入沙箱路径会穿越到其他目录
  static String sanitizePickedFileName(String name) {
    var cleaned = name.replaceAll(RegExp(r'[/\\]'), '_');
    cleaned = cleaned.replaceAll(RegExp(r'\.{2,}'), '_');
    cleaned = cleaned.trim();
    return cleaned.isEmpty ? 'picked_file' : cleaned;
  }

  /// 重名时自动追加序号后缀，避免同名文件静默覆盖沙箱内已有数据
  static String uniqueSandboxFileName(Directory dir, String fileName) {
    if (!File('${dir.path}/$fileName').existsSync()) return fileName;
    final dot = fileName.lastIndexOf('.');
    final stem = dot > 0 ? fileName.substring(0, dot) : fileName;
    final ext = dot > 0 ? fileName.substring(dot) : '';
    var seq = 1;
    while (true) {
      final candidate = '$stem($seq)$ext';
      if (!File('${dir.path}/$candidate').existsSync()) return candidate;
      seq++;
    }
  }

  /// 核对沙箱在追加 [additionalBytes] 后是否仍处于存储配额内
  @visibleForTesting
  bool hasQuotaFor(int additionalBytes) {
    final maxBytes = storageQuotaMb * 1024 * 1024;
    return _sandboxUsedBytes() + additionalBytes <= maxBytes;
  }

  int _sandboxUsedBytes() {
    var bytes = 0;
    try {
      if (pluginRootDir.existsSync()) {
        for (final entity
            in pluginRootDir.listSync(recursive: true, followLinks: false)) {
          if (entity is File) bytes += entity.lengthSync();
        }
      }
    } catch (_) {}
    return bytes;
  }

  Future<String?> _pickAndCopyIntoSandbox({
    List<String>? allowedExtensions,
    required FileType type,
    required String op,
  }) async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: (allowedExtensions != null && allowedExtensions.isNotEmpty)
            ? FileType.custom
            : type,
        allowedExtensions: allowedExtensions,
      );
      if (res == null || res.files.isEmpty) return null;
      final file = res.files.first;
      final srcPath = file.path;
      if (srcPath == null) return null;

      final fileName = sanitizePickedFileName(file.name);
      final destDir = Directory('${pluginRootDir.path}/data');
      if (!destDir.existsSync()) {
        destDir.createSync(recursive: true);
      }

      final srcFile = File(srcPath);
      // 写入前核对配额：单个大文件可直接撑爆插件沙箱额度
      final srcBytes = await srcFile.length();
      if (!hasQuotaFor(srcBytes)) {
        _logger?.w(
            'PluginNativeBridge: $op 超出沙箱配额 ($storageQuotaMb MB)，拒绝写入 $fileName ($srcBytes 字节)');
        return null;
      }

      final uniqueName = uniqueSandboxFileName(destDir, fileName);
      await srcFile.copy('${destDir.path}/$uniqueName');
      return 'data/$uniqueName';
    } catch (e, st) {
      _logError(op, e, st);
      return null;
    }
  }

  void dispose() {
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
    } catch (e, st) {
      _logError('shareText', e, st);
    }
  }

  Future<bool> openUrl(String url) async {
    // 仅放行 http/https：插件可构造 intent://、file://、tel: 等任意 scheme，
    // 不做白名单即可借宿主之手唤起任意组件或读取本地文件
    final uri = Uri.tryParse(url.trim());
    final scheme = uri?.scheme.toLowerCase() ?? '';
    if (uri == null || (scheme != 'http' && scheme != 'https')) {
      _logger?.w('PluginNativeBridge: openUrl 拒绝非 http(s) 链接: $url');
      return false;
    }
    return _invoke<bool>('openUrl', false, {'url': url});
  }

  Future<bool> setTorch(bool enabled) async {
    _torchOn = enabled;
    try {
      final res = await _nativeChannel
          .invokeMethod<bool>('setTorch', {'enabled': enabled});
      return res ?? true;
    } catch (e, st) {
      _logError('setTorch', e, st);
      // 调用失败需回滚内存态，避免 dispose 时向已失效的手电筒重复发关闭指令
      _torchOn = !enabled;
      return false;
    }
  }

  Future<bool> shareFile(
    String filePath, {
    String? mimeType,
    String? subject,
  }) async {
    final resolved = _resolveSandboxPath(filePath, 'shareFile');
    if (resolved == null) return false;
    return _invoke<bool>('shareFile', false, {
      'path': resolved,
      'mimeType': mimeType,
      'subject': subject,
    });
  }

  Future<bool> saveToGallery(String filePath) async {
    final resolved = _resolveSandboxPath(filePath, 'saveToGallery');
    if (resolved == null) return false;
    return _invoke<bool>('saveToGallery', false, {'path': resolved});
  }

  Future<bool> exportFile(String filePath, {String? defaultName}) async {
    final resolved = _resolveSandboxPath(filePath, 'exportFile');
    if (resolved == null) return false;
    return _invoke<bool>('exportFile', false, {
      'path': resolved,
      'defaultName': defaultName,
    });
  }

  // --- 文件与图片选择与沙箱写入 ---
  Future<String?> pickFile({List<String>? allowedExtensions}) {
    return _pickAndCopyIntoSandbox(
      allowedExtensions: allowedExtensions,
      type: FileType.any,
      op: 'pickFile',
    );
  }

  Future<String?> pickImage() {
    return _pickAndCopyIntoSandbox(
      type: FileType.image,
      op: 'pickImage',
    );
  }

  // --- 条码识别 ---
  Future<String?> scanBarcode({String? prompt}) {
    return _invoke<String?>('scanBarcode', null, {'prompt': prompt});
  }

  Future<String?> decodeBarcodeFromImage(String filePath) async {
    final resolved = _resolveSandboxPath(filePath, 'decodeBarcodeFromImage');
    if (resolved == null) return null;
    return _invoke<String?>('decodeBarcodeFromImage', null, {'path': resolved});
  }

  // --- 传感器交互 ---
  Future<bool> startSensor(String type) {
    return _invoke<bool>('startSensor', false, {'type': type});
  }

  Future<bool> stopSensor(String type) {
    return _invoke<bool>('stopSensor', false, {'type': type});
  }

  Future<Map<String, dynamic>?> getSensorData(String type) async {
    final res = await _invokeMap('getSensorData', {'type': type});
    // 原生读取失败时回落到最近一次成功值，避免传感器瞬时抖动打断 UI 刷新
    if (res != null) {
      _sensorCache[type] = res;
    }
    return res ?? _sensorCache[type];
  }

  // --- 媒体图像处理 ---
  Future<Map<String, dynamic>?> imageInfo(String filePath) async {
    final resolved = _resolveSandboxPath(filePath, 'imageInfo');
    if (resolved == null) return null;
    return _invokeMap('imageInfo', {'path': resolved});
  }

  Future<bool> compressImage(
    String srcPath,
    String destPath, {
    int quality = 80,
  }) async {
    final src = _resolveSandboxPath(srcPath, 'compressImage.src');
    final dest = _resolveSandboxPath(destPath, 'compressImage.dest');
    if (src == null || dest == null) return false;
    return _invoke<bool>('compressImage', false, {
      'src': src,
      'dest': dest,
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
    final src = _resolveSandboxPath(srcPath, 'cropImage.src');
    final dest = _resolveSandboxPath(destPath, 'cropImage.dest');
    if (src == null || dest == null) return false;
    return _invoke<bool>('cropImage', false, {
      'src': src,
      'dest': dest,
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
    final src = _resolveSandboxPath(srcPath, 'convertImage.src');
    final dest = _resolveSandboxPath(destPath, 'convertImage.dest');
    if (src == null || dest == null) return false;
    return _invoke<bool>('convertImage', false, {
      'src': src,
      'dest': dest,
      'format': format,
    });
  }

  Future<bool> stripExifImage(String srcPath, String destPath) async {
    final src = _resolveSandboxPath(srcPath, 'stripExifImage.src');
    final dest = _resolveSandboxPath(destPath, 'stripExifImage.dest');
    if (src == null || dest == null) return false;
    return _invoke<bool>('stripExifImage', false, {
      'src': src,
      'dest': dest,
    });
  }

  // --- 系统通知 ---
  Future<int> showNotification({
    required String title,
    required String body,
    String? payload,
  }) {
    return _invoke<int>('showNotification', -1, {
      'title': title,
      'body': body,
      'payload': payload,
    });
  }

  Future<int> scheduleNotification({
    required String title,
    required String body,
    required int delaySeconds,
    String? payload,
  }) {
    return _invoke<int>('scheduleNotification', -1, {
      'title': title,
      'body': body,
      'delaySeconds': delaySeconds,
      'payload': payload,
    });
  }

  Future<bool> cancelNotification(int id) {
    return _invoke<bool>('cancelNotification', false, {'id': id});
  }

  Future<bool> cancelAllNotifications() {
    return _invoke<bool>('cancelAllNotifications', false);
  }

  // --- 音频播放与合成 ---
  Future<bool> playAudio(String filePath) async {
    final resolved = _resolveSandboxPath(filePath, 'playAudio');
    if (resolved == null) return false;
    return _invoke<bool>('playAudio', false, {'path': resolved});
  }

  Future<bool> stopAudio() {
    return _invoke<bool>('stopAudio', false);
  }

  Future<bool> playTone(double frequencyHz, int durationMs) {
    return _invoke<bool>('playTone', false, {
      'frequency': frequencyHz,
      'durationMs': durationMs,
    });
  }

  // --- 录音与分贝感知 ---
  Future<bool> startAudioRecording(String destPath) async {
    final resolved = _resolveSandboxPath(destPath, 'startAudioRecording');
    if (resolved == null) return false;
    return _invoke<bool>('startRecording', false, {'path': resolved});
  }

  Future<Map<String, dynamic>?> stopAudioRecording() {
    return _invokeMap('stopRecording');
  }

  Future<double> getAudioDecibel() async {
    final res = await _invokeMap('getRecordingAmplitude');
    final max = res?['max'];
    return max is num ? max.toDouble() : 0.0;
  }

  // --- 语音朗读 (TTS) ---
  Future<bool> speakText(
    String text, {
    String? language,
    double? pitch,
    double? rate,
  }) {
    return _invoke<bool>('speak', false, {
      'text': text,
      'language': language,
      'rate': rate ?? 1.0,
      'pitch': pitch ?? 1.0,
    });
  }

  Future<bool> stopSpeaking() {
    return _invoke<bool>('stopSpeaking', false);
  }

  // --- 屏幕控制与常亮 ---
  Future<bool> setKeepScreenOn(bool enabled) async {
    _screenKeepOn = enabled;
    return _invoke<bool>('setKeepScreenOn', false, {'enabled': enabled});
  }

  Future<bool> setBrightness(double brightness) async {
    _brightnessModified = true;
    return _invoke<bool>('setBrightness', false, {'brightness': brightness});
  }

  Future<double> getBrightness() {
    return _invoke<double>('getBrightness', 1.0);
  }

  Future<bool> resetBrightness() async {
    _brightnessModified = false;
    return _invoke<bool>('resetBrightness', false);
  }

  // --- 电池、网络状态感知 ---

  /// 电量读取失败时返回 -1（未知哨兵值）而非假值 100，
  /// 插件可据负值探测能力缺失并降级
  Future<int> getBatteryLevel() {
    return _invoke<int>('getBatteryLevel', -1);
  }

  Future<String> fetchNetworkType() {
    return _invoke<String>('getNetworkStatus', 'unknown');
  }

  // --- 系统分享接收 ---
  Future<Map<String, dynamic>?> getInitialShare() {
    return _invokeMap('getInitialShare');
  }

  // --- 生物认证 ---
  Future<bool> isBiometricsAvailable() {
    return _invoke<bool>('isBiometricsAvailable', false);
  }

  Future<Map<String, dynamic>> authenticateBiometrics({String? reason}) async {
    try {
      final res = await _nativeChannel.invokeMethod<bool>(
        'authenticateBiometrics',
        {'reason': reason},
      );
      return {'success': res ?? false};
    } catch (e, st) {
      _logError('authenticateBiometrics', e, st);
      return {'success': false, 'error': e.toString()};
    }
  }

  // --- 地理位置 ---
  Future<bool> isLocationAvailable() {
    return _invoke<bool>('isLocationAvailable', false);
  }

  Future<Map<String, dynamic>?> getCurrentPosition() {
    return _invokeMap('getCurrentPosition');
  }

  // --- NFC ---
  Future<bool> isNfcAvailable() {
    return _invoke<bool>('isNfcAvailable', false);
  }

  Future<Map<String, dynamic>?> readNdef() {
    return _invokeMap('readNdef');
  }

  Future<bool> writeNdef(List<Map<String, dynamic>> records) {
    return _invoke<bool>('writeNdef', false, {'records': records});
  }

  // --- 蓝牙低功耗 (BLE) ---
  Future<bool> isBluetoothAvailable() {
    return _invoke<bool>('isBluetoothAvailable', false);
  }

  /// 原生侧扫描到 BLE 设备后经同一通道回调下发，桥接层分发至 Lua 侧回调
  void _ensureNativeCallbackHandler() {
    if (_nativeCallbackRegistered) return;
    _nativeCallbackRegistered = true;
    _nativeChannel.setMethodCallHandler(handleNativeCallback);
  }

  /// 处理原生侧主动回调（目前仅 BLE 扫描设备发现事件）
  @visibleForTesting
  Future<dynamic> handleNativeCallback(MethodCall call) async {
    if (call.method == 'onBluetoothDeviceFound') {
      final args = call.arguments;
      if (args is Map) {
        _onBluetoothDeviceFound?.call(Map<String, dynamic>.from(args));
      }
    }
    return null;
  }

  Future<bool> startBluetoothScan(
      void Function(Map<String, dynamic> device) onDeviceFound) async {
    _onBluetoothDeviceFound = onDeviceFound;
    _ensureNativeCallbackHandler();
    return _invoke<bool>('startBluetoothScan', false);
  }

  Future<bool> stopBluetoothScan() async {
    _onBluetoothDeviceFound = null;
    return _invoke<bool>('stopBluetoothScan', false);
  }

  Future<bool> connectBluetooth(String deviceId) {
    return _invoke<bool>('connectBluetooth', false, {'deviceId': deviceId});
  }

  Future<bool> disconnectBluetooth(String deviceId) {
    return _invoke<bool>('disconnectBluetooth', false, {'deviceId': deviceId});
  }

  Future<String?> readBluetoothCharacteristic(
    String deviceId,
    String serviceUuid,
    String charUuid,
  ) {
    return _invoke<String?>('readBluetoothCharacteristic', null, {
      'deviceId': deviceId,
      'serviceUuid': serviceUuid,
      'charUuid': charUuid,
    });
  }

  Future<bool> writeBluetoothCharacteristic(
    String deviceId,
    String serviceUuid,
    String charUuid,
    String value,
  ) {
    return _invoke<bool>('writeBluetoothCharacteristic', false, {
      'deviceId': deviceId,
      'serviceUuid': serviceUuid,
      'charUuid': charUuid,
      'value': value,
    });
  }

  // --- 离线 OCR ---
  Future<Map<String, dynamic>?> recognizeText(String filePath) async {
    final resolved = _resolveSandboxPath(filePath, 'recognizeText');
    if (resolved == null) return null;
    if (!File(resolved).existsSync()) return null;
    return _invokeMap('recognizeText', {'path': resolved});
  }

  // --- 宿主统一 AI 网关 ---
  Future<bool> isAiAvailable() {
    return _invoke<bool>('isAiAvailable', false);
  }

  Future<Map<String, dynamic>> aiChat({
    required List<Map<String, dynamic>> messages,
    String? model,
    double? temperature,
  }) async {
    final res = await _invokeMap('aiChat', {
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
    // 原生侧尚无流式增量通道：返回错误流而非静默空流，
    // 让插件在 onError 中探测到能力缺失并降级到 aiChat
    return Stream.error(
        UnimplementedError('aiStreamChat 流式对话尚未实现，请降级使用 aiChat'));
  }

  // --- 系统运行时动态权限 ---
  Future<bool> hasSystemPermission(String permission) {
    return _invoke<bool>('hasPermission', false, {'permission': permission});
  }

  Future<bool> requestSystemPermission(String permission) {
    return _invoke<bool>(
        'requestPermission', false, {'permission': permission});
  }
}
