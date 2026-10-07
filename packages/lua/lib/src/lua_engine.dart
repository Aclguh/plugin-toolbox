import 'package:lua_dardo/lua.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';
import 'api/state_api.dart';
import 'api/clipboard_api.dart';
import 'api/storage_api.dart';
import 'api/network_api.dart';
import 'api/dialog_api.dart';
import 'api/codec_api.dart';
import 'api/json_api.dart';
import 'api/hash_api.dart';
import 'api/util_api.dart';
import 'api/system_api.dart';
import 'api/haptic_api.dart';
import 'api/ui_api.dart';
import 'api/timer_api.dart';
import 'api/share_api.dart';
import 'api/media_api.dart';
import 'api/fs_api.dart';
import 'api/crypto_api.dart';
import 'api/regex_api.dart';
import 'api/color_api.dart';
import 'api/archive_api.dart';
import 'api/document_api.dart';
import 'api/torch_api.dart';
import 'api/qrcode_api.dart';
import 'api/camera_api.dart';
import 'api/vision_api.dart';
import 'api/sensor_api.dart';
import 'api/image_api.dart';
import 'api/notification_api.dart';
import 'api/audio_api.dart';
import 'api/socket_api.dart';
import 'api/websocket_api.dart';
import 'api/biometrics_api.dart';
import 'api/task_api.dart';
import 'api/screen_api.dart';
import 'api/location_api.dart';
import 'api/nfc_api.dart';
import 'api/bluetooth_api.dart';
import 'api/database_api.dart';
import 'api/ai_api.dart';
import 'api/ipc_api.dart';
import 'lua_callback_invoker.dart';
import 'lua_value_codec.dart';

/// 插件与宿主 UI 的双向交互委托契约
abstract class LuaHostDelegate {
  /// 状态变更通知回调
  void onStateChanged(String key, dynamic value);

  /// 获取指定键的当前状态值
  dynamic getState(String key);

  /// 获取当前所有状态键值对映射
  Map<String, dynamic> getAllStates();

  /// 弹出 Toast 提示
  void showToast(String message);

  /// 弹出对话框提示
  Future<void> showAlert(String title, String message);

  /// 弹出带确认与取消选项的二次确认框
  Future<bool> showConfirm(String title, String message);

  /// 收起软键盘
  void hideKeyboard() {}

  /// 触觉反馈 (light, medium, heavy, selection, vibrate)
  void hapticFeedback(String type) {}

  /// 系统分享文本
  Future<void> shareText(String text, {String? subject}) async {}

  /// 打开系统外部浏览器或应用链接
  Future<bool> openUrl(String url) async => false;

  /// 选取外部文件并安全复制至沙箱（返回沙箱内相对路径）
  Future<String?> pickFile({List<String>? allowedExtensions}) async => null;

  /// 选取相册图片并安全复制至沙箱（返回沙箱内相对路径）
  Future<String?> pickImage() async => null;

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

  /// 保存沙箱图片至系统相册 (返回是否保存成功)
  Future<bool> saveToGallery(String filePath) async => false;

  /// 导出沙箱文件至系统公共下载目录 (返回是否导出成功)
  Future<bool> exportFile(
    String filePath, {
    String? defaultName,
  }) async =>
      false;

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

  /// 调起摄像头扫码，返回识别出的文本内容（取消或识别失败返回 null）
  Future<String?> scanBarcode({String? prompt}) async => null;

  /// 对沙箱内的图片进行条形码/二维码解码，返回识别出的文本（未识别出返回 null）
  Future<String?> decodeBarcodeFromImage(String filePath) async => null;

  /// 启动指定类型的传感器监听 (accelerometer, gyroscope, magnetometer, compass)
  Future<bool> startSensor(String type) async => false;

  /// 停止指定类型的传感器监听
  Future<bool> stopSensor(String type) async => false;

  /// 获取指定传感器的最新数据
  Future<Map<String, dynamic>?> getSensorData(String type) async => null;

  // ---- 媒体图像处理 (P2) ----
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

  // ---- 系统通知与定时调度 (P2) ----
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

  // ---- 音频播放与频率发生器 (P2) ----
  /// 播放沙箱内音频文件
  Future<bool> playAudio(String filePath) async => false;

  /// 停止音频播放
  Future<bool> stopAudio() async => false;

  /// 播放指定频率与时长的合成音 (正弦波)
  Future<bool> playTone(double frequencyHz, int durationMs) async => false;

  // ---- 高级交互弹窗 (P3) ----
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

  // ---- 硬件与系统深度状态感知 (P3) ----
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

  // ---- 生物认证与端侧交互 ----
  /// 查询当前设备是否支持生物认证且已录入凭据
  Future<bool> isBiometricsAvailable() async => false;

  /// 发起生物认证核验 (返回 Map: {'success': bool, 'error': String?})
  Future<Map<String, dynamic>> authenticateBiometrics({String? reason}) async =>
      {'success': false, 'error': 'not_supported'};

  // ---- 麦克风录音与声音分贝感知 ----
  /// 开始录音至沙箱目标路径 (返回是否成功)
  Future<bool> startAudioRecording(String destPath) async => false;

  /// 停止录音并返回录音文件信息 (Map: {'ok': bool, 'path': String, 'durationMs': int})
  Future<Map<String, dynamic>?> stopAudioRecording() async => null;

  /// 获取当前环境实时声音分贝值 (0.0 ~ 120.0 dB)
  Future<double> getAudioDecibel() async => 0.0;

  // ---- 语音合成 (TTS) ----
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

  // ---- 屏幕控制与常亮 (Screen) ----
  /// 控制屏幕常亮开关 (返回是否设置成功)
  Future<bool> setKeepScreenOn(bool enabled) async => false;

  /// 调节屏幕亮度 (0.0 ~ 1.0)
  Future<bool> setBrightness(double brightness) async => false;

  /// 获取当前屏幕亮度 (0.0 ~ 1.0)
  Future<double> getBrightness() async => 1.0;

  /// 重置屏幕亮度为系统默认
  Future<bool> resetBrightness() async => false;

  // ---- 系统分享接收 (Share Target) ----
  /// 获取由系统分享传入应用的初始数据
  Future<Map<String, dynamic>?> getInitialShare() async => null;

  // ---- 地理位置与海拔 (Location) ----
  /// 查询定位服务是否可用
  Future<bool> isLocationAvailable() async => false;

  /// 获取当前地理位置坐标与海拔数据
  Future<Map<String, dynamic>?> getCurrentPosition() async => null;

  // ---- NFC 近场通信 ----
  /// 查询当前设备是否支持 NFC
  Future<bool> isNfcAvailable() async => false;

  /// 读取当前感应到的 NFC NDEF 标签数据
  Future<Map<String, dynamic>?> readNdef() async => null;

  /// 向感应到的 NFC 标签写入 NDEF 记录
  Future<bool> writeNdef(List<Map<String, dynamic>> records) async => false;

  // ---- 蓝牙低功耗 (Bluetooth LE) ----
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

  // ---- 离线 OCR 图像文字识别 ----
  /// 对沙箱内的图片进行文字识别
  Future<Map<String, dynamic>?> recognizeText(String filePath) async => null;

  // ---- 宿主统一 AI 网关 ----
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

  // ---- 跨插件互通与管道调起 ----
  /// 唤起并打开目标插件 (可携带初始参数)
  Future<bool> openPlugin(
    String targetPluginId, {
    Map<String, dynamic>? initialData,
  }) async =>
      false;
}

/// 安全隔离的 Lua 运行时引擎，提供宿主 API 绑定注入与指令数死循环预算保护
class LuaEngine {
  final PluginContext context;
  final LuaHostDelegate delegate;

  /// 单次 Lua 闭包执行允许的最大虚拟机指令条数，防止 `while true do end`
  /// 类死循环永久冻结宿主主线程；超限抛出异常并由 pCall 降级为执行错误。
  static const int defaultInstructionBudget = 5000000;

  final int instructionBudget;

  late final LuaState _ls;
  LuaCallbackInvoker? _callbacks;
  TimerApi? _timerApi;
  SensorApi? _sensorApi;
  SocketApi? _socketApi;
  WebSocketApi? _webSocketApi;
  bool _closed = false;

  /// 引擎是否已被关闭
  bool get isClosed => _closed;

  LuaEngine({
    required this.context,
    required this.delegate,
    this.instructionBudget = defaultInstructionBudget,
  }) {
    _ls = LuaState.newState();
    _ls.openLibs();
    _registerSecuritySandbox();
    _registerHostApis();
  }

  /// 封禁具有潜在安全风险的 Lua 标准库。
  ///
  /// lua_dardo 的 openLibs 会注册 base/table/string/math/os/package：
  /// `os.execute`/`os.remove`/`io` 文件操作可执行任意系统命令与读写任意文件，
  /// `require`/`dofile`/`loadfile` 可从磁盘加载任意脚本，`debug`/`package`
  /// 可触达虚拟机内部。全部置 nil 以彻底封堵沙箱逃逸面。
  void _registerSecuritySandbox() {
    for (final lib in ['os', 'io', 'debug', 'package', 'require', 'dofile', 'loadfile']) {
      _ls.pushNil();
      _ls.setGlobal(lib);
    }
  }

  /// 注册所有受白名单权限控制的宿主 API
  void _registerHostApis() {
    _callbacks = LuaCallbackInvoker(_ls, instructionBudget);
    void writeState(String key, dynamic value) =>
        delegate.onStateChanged(key, value);

    _timerApi = TimerApi();
    _timerApi!.bind(_ls, _callbacks!);

    StateApi.bind(_ls, delegate);
    ClipboardApi.bind(_ls, context, _callbacks!, writeState);
    StorageApi.bind(_ls, context, _callbacks!, writeState);
    NetworkApi.bind(_ls, context, _callbacks!, writeState);
    DialogApi.bind(_ls, delegate, _callbacks!);
    CodecApi.bind(_ls);
    JsonApi.bind(_ls);
    HashApi.bind(_ls);
    UtilApi.bind(_ls);
    SystemApi.bind(_ls, delegate, _callbacks!);
    HapticApi.bind(_ls, delegate);
    UiApi.bind(_ls, delegate);
    ShareApi.bind(_ls, delegate, context, _callbacks!);
    MediaApi.bind(_ls, context, delegate, _callbacks!, writeState);
    FsApi.bind(_ls, context, delegate, _callbacks!);
    CryptoApi.bind(_ls);
    RegexApi.bind(_ls);
    ColorApi.bind(_ls);
    ArchiveApi.bind(_ls, context);
    DocumentApi.bind(_ls);
    TorchApi.bind(_ls, context, delegate, _callbacks!);
    QrcodeApi.bind(_ls);
    CameraApi.bind(_ls, context, delegate, _callbacks!);
    VisionApi.bind(_ls, context, delegate, _callbacks!);
    _sensorApi = SensorApi();
    _sensorApi!.bind(_ls, context, delegate, _callbacks!);
    ImageApi.bind(_ls, context, delegate, _callbacks!);
    NotificationApi.bind(_ls, context, delegate, _callbacks!);
    AudioApi.bind(_ls, context, delegate, _callbacks!);
    _socketApi = SocketApi();
    _socketApi!.bind(_ls, context, _callbacks!);
    _webSocketApi = WebSocketApi();
    _webSocketApi!.bind(_ls, context, _callbacks!);
    BiometricsApi.bind(_ls, context, delegate, _callbacks!);
    TaskApi.bind(_ls, context, _callbacks!);
    ScreenApi.bind(_ls, context, delegate, _callbacks!);
    LocationApi.bind(_ls, context, delegate, _callbacks!);
    NfcApi.bind(_ls, context, delegate, _callbacks!);
    BluetoothApi.bind(_ls, context, delegate, _callbacks!);
    DatabaseApi.bind(_ls, context, _callbacks!);
    AiApi.bind(_ls, context, delegate, _callbacks!);
    IpcApi.bind(_ls, context, delegate, _callbacks!);
  }

  /// 执行 Lua 源代码字符串
  void loadAndExecute(String scriptContent) {
    if (_closed) {
      throw StateError('Cannot use closed LuaEngine');
    }
    _ls.setInstructionBudget(instructionBudget);
    final status = _ls.loadString(scriptContent);
    if (status != ThreadStatus.luaOk) {
      final errorMsg = _ls.toStr(-1) ?? 'Unknown syntax error';
      throw Exception('Lua 编译错误: $errorMsg');
    }
    final pcallStatus = _ls.pCall(0, 0, 0);
    if (pcallStatus != ThreadStatus.luaOk) {
      final errorMsg = _ls.toStr(-1) ?? 'Unknown runtime error';
      throw Exception('Lua 执行错误: $errorMsg');
    }
  }

  /// 调用 Lua 全局函数
  dynamic callFunction(String funcName, [List<dynamic> args = const []]) {
    if (_closed) {
      throw StateError('Cannot use closed LuaEngine');
    }
    final type = _ls.getGlobal(funcName);
    if (type != LuaType.luaFunction) {
      _ls.pop(1);
      return null;
    }

    for (final arg in args) {
      _pushValue(arg);
    }

    _ls.setInstructionBudget(instructionBudget);
    final status = _ls.pCall(args.length, 1, 0);
    if (status != ThreadStatus.luaOk) {
      final err = _ls.toStr(-1) ?? 'Error in function $funcName';
      _ls.pop(1);
      throw Exception('调用 Lua 函数 [$funcName] 失败: $err');
    }

    final res = _popValue();
    return res;
  }

  void _pushValue(dynamic val, [Set<Object?>? visited]) =>
      LuaValueCodec.push(_ls, val, visited);

  dynamic _popValue() => LuaValueCodec.pop(_ls);

  /// 关闭引擎并释放所持有的注册表回调引用与资源。
  /// 关闭后再调用执行操作将抛出 [StateError]。
  void close() {
    if (_closed) return;
    _closed = true;
    PluginIpcBroker.instance.unregisterService(context.pluginId);
    delegate.stopAudio();
    delegate.stopBluetoothScan();
    delegate.setKeepScreenOn(false);
    delegate.resetBrightness();
    _sensorApi?.dispose(delegate, _callbacks!);
    _timerApi?.dispose(_callbacks);
    _socketApi?.dispose(_callbacks);
    _webSocketApi?.dispose(_callbacks);
    _callbacks?.clear();
  }
}
