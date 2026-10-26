import 'dart:async';

/// 插件状态响应与管理委托契约
abstract class LuaStateDelegate {
  /// 状态变更通知回调
  void onStateChanged(String key, dynamic value);

  /// 获取指定键的当前状态值
  dynamic getState(String key);

  /// 获取当前所有状态键值对映射
  Map<String, dynamic> getAllStates();
}

/// 插件 UI 弹窗与交互提示委托契约
abstract class LuaUiDelegate {
  /// 弹出 Toast 提示
  void showToast(String message);

  /// 弹出对话框提示
  Future<void> showAlert(String title, String message);

  /// 弹出带确认与取消选项的二次确认框
  Future<bool> showConfirm(String title, String message);

  /// 收起软键盘
  void hideKeyboard() {}

  /// 弹出原生日期选择器 (返回 YYYY-MM-DD 格式，取消返回 null)
  Future<String?> pickDate({
    String? initialDate,
    String? firstDate,
    String? lastDate,
  }) async =>
      null;

  /// 弹出原生时间选择器 (返回 24小时制 HH:mm 格式，取消返回 null)
  Future<String?> pickTime({
    String? initialTime,
  }) async =>
      null;

  /// 弹出文本输入提示弹窗 (返回输入文本，取消返回 null)
  Future<String?> showPrompt({
    required String title,
    String? hint,
    String? defaultValue,
  }) async =>
      null;

  /// 弹出单选列表弹窗 (返回选中项 Map: {'index': int, 'text': String}，取消返回 null)
  Future<Map<String, dynamic>?> showPickItem({
    required String title,
    required List<String> items,
    int initialIndex = 0,
  }) async =>
      null;

  /// 弹出底部动作面板 (Modal Bottom Sheet)，返回选中项 Map: {'index': int, 'text': String}，取消返回 null
  Future<Map<String, dynamic>?> showBottomSheet({
    required String title,
    required List<String> items,
  }) async =>
      null;
}

/// 插件媒体与图像/音频处理委托契约
abstract class LuaMediaDelegate {
  /// 选取外部文件并安全复制至沙箱（返回沙箱内相对路径）
  Future<String?> pickFile({List<String>? allowedExtensions}) async => null;

  /// 选取相册图片并安全复制至沙箱（返回沙箱内相对路径）
  Future<String?> pickImage() async => null;

  /// 保存沙箱图片至系统相册 (返回是否保存成功)
  Future<bool> saveToGallery(String filePath) async => false;

  /// 导出沙箱文件至系统公共下载目录 (返回是否导出成功)
  Future<bool> exportFile(
    String filePath, {
    String? defaultName,
  }) async =>
      false;

  /// 调起摄像头扫码，返回识别出的文本内容（取消或识别失败返回 null）
  Future<String?> scanBarcode({String? prompt}) async => null;

  /// 对沙箱内的图片进行条形码/二维码解码，返回识别出的文本（未识别出返回 null）
  Future<String?> decodeBarcodeFromImage(String filePath) async => null;

  /// 获取沙箱图片的元数据 (width, height, format, size)
  Future<Map<String, dynamic>?> imageInfo(String filePath) async => null;

  /// 压缩图片并写入目标路径 (返回是否成功)
  Future<bool> compressImage(
    String srcPath,
    String destPath, {
    int quality = 80,
  }) async =>
      false;

  /// 裁剪图片并写入目标路径 (返回是否成功)
  Future<bool> cropImage(
    String srcPath,
    String destPath, {
    required int x,
    required int y,
    required int width,
    required int height,
  }) async =>
      false;

  /// 转换图片格式并写入目标路径 (返回是否成功)
  Future<bool> convertImage(
    String srcPath,
    String destPath, {
    required String format,
  }) async =>
      false;

  /// 擦除图片 EXIF 元数据并重写保存 (返回是否成功)
  Future<bool> stripExifImage(String srcPath, String destPath) async => false;

  /// 播放沙箱内音频文件
  Future<bool> playAudio(String filePath) async => false;

  /// 停止音频播放
  Future<bool> stopAudio() async => false;

  /// 播放指定频率与时长的合成音 (正弦波)
  Future<bool> playTone(double frequencyHz, int durationMs) async => false;

  /// 开始录音至沙箱目标路径 (返回是否成功)
  Future<bool> startAudioRecording(String destPath) async => false;

  /// 停止录音并返回录音文件信息 (Map: {'ok': bool, 'path': String, 'durationMs': int})
  Future<Map<String, dynamic>?> stopAudioRecording() async => null;

  /// 获取当前环境实时声音分贝值 (0.0 ~ 120.0 dB)
  Future<double> getAudioDecibel() async => 0.0;

  /// 朗读文本 (返回是否成功发起)
  Future<bool> speakText(
    String text, {
    String? language,
    double? pitch,
    double? rate,
  }) async =>
      false;

  /// 停止当前语音朗读
  Future<bool> stopSpeaking() async => false;

  /// 对沙箱内的图片进行文字识别
  Future<Map<String, dynamic>?> recognizeText(String filePath) async => null;

  /// 拍照并保存至沙箱目标路径，返回保存后的沙箱绝对路径 (取消或失败返回 null)
  Future<String?> takePhoto({
    String? destPath,
    int quality = 90,
    String lensDirection = 'back',
  }) async =>
      null;

  /// 截取当前插件视图或指定组件区域并保存至沙箱目标路径 (返回是否成功)
  Future<bool> captureScreen({
    required String destPath,
    String? targetRef,
  }) async =>
      false;
}

/// 插件系统与硬件底层外设委托契约
abstract class LuaDeviceDelegate {
  /// 触觉反馈 (light, medium, heavy, selection, vibrate)
  void hapticFeedback(String type) {}

  /// 系统分享文本
  Future<void> shareText(String text, {String? subject}) async {}

  /// 打开系统外部浏览器或应用链接
  Future<bool> openUrl(String url) async => false;

  /// 控制设备手电筒/闪光灯开关 (返回是否操作成功)
  Future<bool> setTorch(bool enabled) async => false;

  /// 查询手电筒当前开关状态
  bool get isTorchOn => false;

  /// 系统分享沙箱文件
  Future<bool> shareFile(
    String filePath, {
    String? mimeType,
    String? subject,
  }) async =>
      false;

  /// 启动指定类型的传感器监听 (accelerometer, gyroscope, magnetometer, compass)
  Future<bool> startSensor(String type) async => false;

  /// 停止指定类型的传感器监听
  Future<bool> stopSensor(String type) async => false;

  /// 获取指定传感器的最新数据
  Future<Map<String, dynamic>?> getSensorData(String type) async => null;

  /// 发送即时本地系统通知 (返回通知 ID)
  Future<int> showNotification({
    required String title,
    required String body,
    String? payload,
  }) async =>
      -1;

  /// 安排定时本地系统通知 (返回通知 ID)
  Future<int> scheduleNotification({
    required String title,
    required String body,
    required int delaySeconds,
    String? payload,
  }) async =>
      -1;

  /// 取消指定 ID 的本地系统通知
  Future<bool> cancelNotification(int id) async => false;

  /// 取消当前插件产生的所有系统通知
  Future<bool> cancelAllNotifications() async => false;

  /// 获取当前电池电量百分比 (0 ~ 100)
  int get batteryLevel => 100;

  /// 查询当前是否处于充电状态
  bool get isCharging => false;

  /// 查询当前网络连接类型 ('wifi', 'cellular', 'none', 'unknown')
  String get networkType => 'unknown';

  /// 异步获取电池电量百分比
  Future<int> getBatteryLevel() async => batteryLevel;

  /// 异步查询充电状态
  Future<bool> checkIsCharging() async => isCharging;

  /// 异步查询网络连接类型
  Future<String> fetchNetworkType() async => networkType;

  /// 查询当前设备是否支持生物认证且已录入凭据
  Future<bool> isBiometricsAvailable() async => false;

  /// 发起生物认证核验 (返回 Map: {'success': bool, 'error': String?})
  Future<Map<String, dynamic>> authenticateBiometrics({String? reason}) async =>
      {'success': false, 'error': 'not_supported'};

  /// 控制屏幕常亮开关 (返回是否设置成功)
  Future<bool> setKeepScreenOn(bool enabled) async => false;

  /// 调节屏幕亮度 (0.0 ~ 1.0)
  Future<bool> setBrightness(double brightness) async => false;

  /// 获取当前屏幕亮度 (0.0 ~ 1.0)
  Future<double> getBrightness() async => 1.0;

  /// 重置屏幕亮度为系统默认
  Future<bool> resetBrightness() async => false;

  /// 获取由系统分享传入应用的初始数据
  Future<Map<String, dynamic>?> getInitialShare() async => null;

  /// 查询定位服务是否可用
  Future<bool> isLocationAvailable() async => false;

  /// 获取当前地理位置坐标与海拔数据
  Future<Map<String, dynamic>?> getCurrentPosition() async => null;

  /// 查询当前设备是否支持 NFC
  Future<bool> isNfcAvailable() async => false;

  /// 读取当前感应到的 NFC NDEF 标签数据
  Future<Map<String, dynamic>?> readNdef() async => null;

  /// 向感应到的 NFC 标签写入 NDEF 记录
  Future<bool> writeNdef(List<Map<String, dynamic>> records) async => false;

  /// 查询当前设备蓝牙是否就绪可用
  Future<bool> isBluetoothAvailable() async => false;

  /// 启动蓝牙 LE 设备扫描
  Future<bool> startBluetoothScan(
          void Function(Map<String, dynamic> device) onDeviceFound) async =>
      false;

  /// 停止蓝牙 LE 设备扫描
  Future<bool> stopBluetoothScan() async => false;

  /// 连接指定 BLE 设备
  Future<bool> connectBluetooth(String deviceId) async => false;

  /// 断开指定 BLE 设备连接
  Future<bool> disconnectBluetooth(String deviceId) async => false;

  /// 读取 BLE 特征值
  Future<String?> readBluetoothCharacteristic(
    String deviceId,
    String serviceUuid,
    String charUuid,
  ) async =>
      null;

  /// 写入 BLE 特征值
  Future<bool> writeBluetoothCharacteristic(
    String deviceId,
    String serviceUuid,
    String charUuid,
    String value,
  ) async =>
      false;

  /// 唤起并打开目标插件 (可携带初始参数)
  Future<bool> openPlugin(
    String targetPluginId, {
    Map<String, dynamic>? initialData,
  }) async =>
      false;

  /// 获取当前 Wi-Fi 连接详细信息
  Future<Map<String, dynamic>?> getWifiInfo() async => null;

  /// 对目标主机发起网络 Ping 连通与延迟探测
  Future<Map<String, dynamic>> pingHost(
    String host, {
    int timeoutMs = 3000,
  }) async =>
      {'ok': false, 'error': 'not_supported'};
}

/// 宿主大模型与统一 AI 网关委托契约
abstract class LuaAiDelegate {
  /// 查询宿主是否已配置可用 AI 服务
  Future<bool> isAiAvailable() async => false;

  /// 发起 AI 文本生成或多轮对话
  Future<Map<String, dynamic>> aiChat({
    required List<Map<String, dynamic>> messages,
    String? model,
    double? temperature,
  }) async =>
      {'ok': false, 'error': 'AI 网关未配置或服务不可用'};

  /// 发起流式 AI 对话增量输出
  Stream<String> aiStreamChat({
    required List<Map<String, dynamic>> messages,
    String? model,
    double? temperature,
  }) =>
      const Stream.empty();
}

/// 剪贴板读写委托契约（解耦 Flutter 表现层依赖）
abstract class LuaClipboardDelegate {
  /// 写入纯文本至剪贴板
  void setClipboardText(String text) {}

  /// 从剪贴板异步读取纯文本
  Future<String?> getClipboardText() async => null;
}

/// 复合宿主委托契约：继承各个领域专精子接口
abstract class LuaHostDelegate
    implements
        LuaStateDelegate,
        LuaUiDelegate,
        LuaMediaDelegate,
        LuaDeviceDelegate,
        LuaAiDelegate,
        LuaClipboardDelegate {
  /// 当前是否处于无头（Headless）后台运行模式（无前台 UI 挂载）
  bool get isHeadless => false;
}

/// 复合宿主委托适配器：将分领域的各个子委托组合为单一复合实例
class CompositeLuaHostDelegate implements LuaHostDelegate {
  final LuaStateDelegate stateDelegate;
  final LuaUiDelegate? uiDelegate;
  final LuaMediaDelegate? mediaDelegate;
  final LuaDeviceDelegate? deviceDelegate;
  final LuaAiDelegate? aiDelegate;
  final LuaClipboardDelegate? clipboardDelegate;

  CompositeLuaHostDelegate({
    required this.stateDelegate,
    this.uiDelegate,
    this.mediaDelegate,
    this.deviceDelegate,
    this.aiDelegate,
    this.clipboardDelegate,
  });

  @override
  bool get isHeadless => false;

  // State
  @override
  void onStateChanged(String key, dynamic value) =>
      stateDelegate.onStateChanged(key, value);

  @override
  dynamic getState(String key) => stateDelegate.getState(key);

  @override
  Map<String, dynamic> getAllStates() => stateDelegate.getAllStates();

  // UI
  @override
  void showToast(String message) => uiDelegate?.showToast(message);

  @override
  Future<void> showAlert(String title, String message) async =>
      uiDelegate?.showAlert(title, message);

  @override
  Future<bool> showConfirm(String title, String message) async =>
      await uiDelegate?.showConfirm(title, message) ?? false;

  @override
  void hideKeyboard() => uiDelegate?.hideKeyboard();

  @override
  Future<String?> pickDate({
    String? initialDate,
    String? firstDate,
    String? lastDate,
  }) async =>
      await uiDelegate?.pickDate(
          initialDate: initialDate, firstDate: firstDate, lastDate: lastDate);

  @override
  Future<String?> pickTime({String? initialTime}) async =>
      await uiDelegate?.pickTime(initialTime: initialTime);

  @override
  Future<String?> showPrompt({
    required String title,
    String? hint,
    String? defaultValue,
  }) async =>
      await uiDelegate?.showPrompt(
          title: title, hint: hint, defaultValue: defaultValue);

  @override
  Future<Map<String, dynamic>?> showPickItem({
    required String title,
    required List<String> items,
    int initialIndex = 0,
  }) async =>
      await uiDelegate?.showPickItem(
          title: title, items: items, initialIndex: initialIndex);

  @override
  Future<Map<String, dynamic>?> showBottomSheet({
    required String title,
    required List<String> items,
  }) async =>
      await uiDelegate?.showBottomSheet(title: title, items: items);

  // Media
  @override
  Future<String?> pickFile({List<String>? allowedExtensions}) async =>
      await mediaDelegate?.pickFile(allowedExtensions: allowedExtensions);

  @override
  Future<String?> pickImage() async => await mediaDelegate?.pickImage();

  @override
  Future<bool> saveToGallery(String filePath) async =>
      await mediaDelegate?.saveToGallery(filePath) ?? false;

  @override
  Future<bool> exportFile(String filePath, {String? defaultName}) async =>
      await mediaDelegate?.exportFile(filePath, defaultName: defaultName) ??
      false;

  @override
  Future<String?> scanBarcode({String? prompt}) async =>
      await mediaDelegate?.scanBarcode(prompt: prompt);

  @override
  Future<String?> decodeBarcodeFromImage(String filePath) async =>
      await mediaDelegate?.decodeBarcodeFromImage(filePath);

  @override
  Future<Map<String, dynamic>?> imageInfo(String filePath) async =>
      await mediaDelegate?.imageInfo(filePath);

  @override
  Future<bool> compressImage(String srcPath, String destPath,
          {int quality = 80}) async =>
      await mediaDelegate?.compressImage(srcPath, destPath, quality: quality) ??
      false;

  @override
  Future<bool> cropImage(String srcPath, String destPath,
          {required int x,
          required int y,
          required int width,
          required int height}) async =>
      await mediaDelegate?.cropImage(srcPath, destPath,
          x: x, y: y, width: width, height: height) ??
      false;

  @override
  Future<bool> convertImage(String srcPath, String destPath,
          {required String format}) async =>
      await mediaDelegate?.convertImage(srcPath, destPath, format: format) ??
      false;

  @override
  Future<bool> stripExifImage(String srcPath, String destPath) async =>
      await mediaDelegate?.stripExifImage(srcPath, destPath) ?? false;

  @override
  Future<bool> playAudio(String filePath) async =>
      await mediaDelegate?.playAudio(filePath) ?? false;

  @override
  Future<bool> stopAudio() async => await mediaDelegate?.stopAudio() ?? false;

  @override
  Future<bool> playTone(double frequencyHz, int durationMs) async =>
      await mediaDelegate?.playTone(frequencyHz, durationMs) ?? false;

  @override
  Future<bool> startAudioRecording(String destPath) async =>
      await mediaDelegate?.startAudioRecording(destPath) ?? false;

  @override
  Future<Map<String, dynamic>?> stopAudioRecording() async =>
      await mediaDelegate?.stopAudioRecording();

  @override
  Future<double> getAudioDecibel() async =>
      await mediaDelegate?.getAudioDecibel() ?? 0.0;

  @override
  Future<bool> speakText(String text,
          {String? language, double? pitch, double? rate}) async =>
      await mediaDelegate?.speakText(text,
          language: language, pitch: pitch, rate: rate) ??
      false;

  @override
  Future<bool> stopSpeaking() async =>
      await mediaDelegate?.stopSpeaking() ?? false;

  @override
  Future<Map<String, dynamic>?> recognizeText(String filePath) async =>
      await mediaDelegate?.recognizeText(filePath);

  @override
  Future<String?> takePhoto({
    String? destPath,
    int quality = 90,
    String lensDirection = 'back',
  }) async =>
      await mediaDelegate?.takePhoto(
        destPath: destPath,
        quality: quality,
        lensDirection: lensDirection,
      );

  @override
  Future<bool> captureScreen({
    required String destPath,
    String? targetRef,
  }) async =>
      await mediaDelegate?.captureScreen(
        destPath: destPath,
        targetRef: targetRef,
      ) ??
      false;

  // Device
  @override
  void hapticFeedback(String type) => deviceDelegate?.hapticFeedback(type);

  @override
  Future<void> shareText(String text, {String? subject}) async =>
      await deviceDelegate?.shareText(text, subject: subject);

  @override
  Future<bool> openUrl(String url) async =>
      await deviceDelegate?.openUrl(url) ?? false;

  @override
  Future<bool> setTorch(bool enabled) async =>
      await deviceDelegate?.setTorch(enabled) ?? false;

  @override
  bool get isTorchOn => deviceDelegate?.isTorchOn ?? false;

  @override
  Future<bool> shareFile(String filePath,
          {String? mimeType, String? subject}) async =>
      await deviceDelegate?.shareFile(filePath,
          mimeType: mimeType, subject: subject) ??
      false;

  @override
  Future<bool> startSensor(String type) async =>
      await deviceDelegate?.startSensor(type) ?? false;

  @override
  Future<bool> stopSensor(String type) async =>
      await deviceDelegate?.stopSensor(type) ?? false;

  @override
  Future<Map<String, dynamic>?> getSensorData(String type) async =>
      await deviceDelegate?.getSensorData(type);

  @override
  Future<int> showNotification(
          {required String title,
          required String body,
          String? payload}) async =>
      await deviceDelegate?.showNotification(
          title: title, body: body, payload: payload) ??
      -1;

  @override
  Future<int> scheduleNotification(
          {required String title,
          required String body,
          required int delaySeconds,
          String? payload}) async =>
      await deviceDelegate?.scheduleNotification(
          title: title,
          body: body,
          delaySeconds: delaySeconds,
          payload: payload) ??
      -1;

  @override
  Future<bool> cancelNotification(int id) async =>
      await deviceDelegate?.cancelNotification(id) ?? false;

  @override
  Future<bool> cancelAllNotifications() async =>
      await deviceDelegate?.cancelAllNotifications() ?? false;

  @override
  int get batteryLevel => deviceDelegate?.batteryLevel ?? 100;

  @override
  bool get isCharging => deviceDelegate?.isCharging ?? false;

  @override
  String get networkType => deviceDelegate?.networkType ?? 'unknown';

  @override
  Future<int> getBatteryLevel() async =>
      await deviceDelegate?.getBatteryLevel() ?? batteryLevel;

  @override
  Future<bool> checkIsCharging() async =>
      await deviceDelegate?.checkIsCharging() ?? isCharging;

  @override
  Future<String> fetchNetworkType() async =>
      await deviceDelegate?.fetchNetworkType() ?? networkType;

  @override
  Future<bool> isBiometricsAvailable() async =>
      await deviceDelegate?.isBiometricsAvailable() ?? false;

  @override
  Future<Map<String, dynamic>> authenticateBiometrics({String? reason}) async =>
      await deviceDelegate?.authenticateBiometrics(reason: reason) ??
      {'success': false, 'error': 'not_supported'};

  @override
  Future<bool> setKeepScreenOn(bool enabled) async =>
      await deviceDelegate?.setKeepScreenOn(enabled) ?? false;

  @override
  Future<bool> setBrightness(double brightness) async =>
      await deviceDelegate?.setBrightness(brightness) ?? false;

  @override
  Future<double> getBrightness() async =>
      await deviceDelegate?.getBrightness() ?? 1.0;

  @override
  Future<bool> resetBrightness() async =>
      await deviceDelegate?.resetBrightness() ?? false;

  @override
  Future<Map<String, dynamic>?> getInitialShare() async =>
      await deviceDelegate?.getInitialShare();

  @override
  Future<bool> isLocationAvailable() async =>
      await deviceDelegate?.isLocationAvailable() ?? false;

  @override
  Future<Map<String, dynamic>?> getCurrentPosition() async =>
      await deviceDelegate?.getCurrentPosition();

  @override
  Future<bool> isNfcAvailable() async =>
      await deviceDelegate?.isNfcAvailable() ?? false;

  @override
  Future<Map<String, dynamic>?> readNdef() async =>
      await deviceDelegate?.readNdef();

  @override
  Future<bool> writeNdef(List<Map<String, dynamic>> records) async =>
      await deviceDelegate?.writeNdef(records) ?? false;

  @override
  Future<bool> isBluetoothAvailable() async =>
      await deviceDelegate?.isBluetoothAvailable() ?? false;

  @override
  Future<bool> startBluetoothScan(
          void Function(Map<String, dynamic> device) onDeviceFound) async =>
      await deviceDelegate?.startBluetoothScan(onDeviceFound) ?? false;

  @override
  Future<bool> stopBluetoothScan() async =>
      await deviceDelegate?.stopBluetoothScan() ?? false;

  @override
  Future<bool> connectBluetooth(String deviceId) async =>
      await deviceDelegate?.connectBluetooth(deviceId) ?? false;

  @override
  Future<bool> disconnectBluetooth(String deviceId) async =>
      await deviceDelegate?.disconnectBluetooth(deviceId) ?? false;

  @override
  Future<String?> readBluetoothCharacteristic(
          String deviceId, String serviceUuid, String charUuid) async =>
      await deviceDelegate?.readBluetoothCharacteristic(
          deviceId, serviceUuid, charUuid);

  @override
  Future<bool> writeBluetoothCharacteristic(String deviceId, String serviceUuid,
          String charUuid, String value) async =>
      await deviceDelegate?.writeBluetoothCharacteristic(
          deviceId, serviceUuid, charUuid, value) ??
      false;

  @override
  Future<bool> openPlugin(String targetPluginId,
          {Map<String, dynamic>? initialData}) async =>
      await deviceDelegate?.openPlugin(targetPluginId,
          initialData: initialData) ??
      false;

  @override
  Future<Map<String, dynamic>?> getWifiInfo() async =>
      await deviceDelegate?.getWifiInfo();

  @override
  Future<Map<String, dynamic>> pingHost(String host,
          {int timeoutMs = 3000}) async =>
      await deviceDelegate?.pingHost(host, timeoutMs: timeoutMs) ??
      {'ok': false, 'error': 'not_supported'};

  // AI
  @override
  Future<bool> isAiAvailable() async =>
      await aiDelegate?.isAiAvailable() ?? false;

  @override
  Future<Map<String, dynamic>> aiChat(
          {required List<Map<String, dynamic>> messages,
          String? model,
          double? temperature}) async =>
      await aiDelegate?.aiChat(
          messages: messages, model: model, temperature: temperature) ??
      {'ok': false, 'error': 'AI 网关未配置或服务不可用'};

  @override
  Stream<String> aiStreamChat(
          {required List<Map<String, dynamic>> messages,
          String? model,
          double? temperature}) =>
      aiDelegate?.aiStreamChat(
          messages: messages, model: model, temperature: temperature) ??
      const Stream.empty();

  // Clipboard
  @override
  void setClipboardText(String text) =>
      clipboardDelegate?.setClipboardText(text);

  @override
  Future<String?> getClipboardText() async =>
      await clipboardDelegate?.getClipboardText();
}

/// 复合宿主委托标记接口
abstract class LuaHostDelegateProxy
    implements
        LuaStateDelegate,
        LuaUiDelegate,
        LuaMediaDelegate,
        LuaDeviceDelegate,
        LuaAiDelegate,
        LuaClipboardDelegate {}

/// 无头状态委托实现
class HeadlessStateDelegate implements LuaStateDelegate {
  final Map<String, dynamic> _states;
  HeadlessStateDelegate([Map<String, dynamic>? initialStates])
      : _states = Map.from(initialStates ?? {});

  @override
  void onStateChanged(String key, dynamic value) => _states[key] = value;

  @override
  dynamic getState(String key) => _states[key];

  @override
  Map<String, dynamic> getAllStates() => Map.unmodifiable(_states);
}

/// 无头（Headless）后台运行模式的宿主委托实现
///
/// 继承 CompositeLuaHostDelegate，具备内存状态管理与全套安全的静默兜底。
class HeadlessLuaHostDelegate extends CompositeLuaHostDelegate {
  HeadlessLuaHostDelegate({Map<String, dynamic>? initialStates})
      : super(
          stateDelegate: HeadlessStateDelegate(initialStates),
        );

  @override
  bool get isHeadless => true;
}
