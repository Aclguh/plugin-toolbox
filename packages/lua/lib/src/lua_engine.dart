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
import 'api/plugin_database.dart';
import 'api/ai_api.dart';
import 'api/ipc_api.dart';
import 'delegates/domain_delegates.dart';
import 'lua_callback_invoker.dart';
import 'lua_value_codec.dart';

export 'delegates/domain_delegates.dart';
export 'api/plugin_database.dart';

/// 安全隔离的 Lua 运行时引擎，提供宿主 API 绑定注入与指令数死循环预算保护
class LuaEngine {
  final PluginContext context;
  final LuaHostDelegate delegate;

  /// 单次 Lua 闭包执行允许的最大虚拟机指令条数，防止 `while true do end`
  /// 类死循环永久冻结宿主主线程；超限抛出异常并由 pCall 降级为执行错误。
  static const int defaultInstructionBudget = 5000000;

  /// 单个 Lua 虚拟机实例允许的最大堆内存预算（字节），防止巨型 Table 或长字符串
  /// 耗尽宿主内存造成 OOM 强杀。默认 32MB。
  static const int defaultMemoryBudget = 32 * 1024 * 1024;

  final int instructionBudget;
  final int memoryBudget;
  final PluginDatabaseFactory? databaseFactory;
  final void Function(String error)? onCallbackError;

  late final LuaState _ls;
  LuaCallbackInvoker? _callbacks;
  TimerApi? _timerApi;
  SensorApi? _sensorApi;
  SocketApi? _socketApi;
  WebSocketApi? _webSocketApi;
  DatabaseApi? _databaseApi;
  bool _closed = false;

  /// 引擎是否已被关闭
  bool get isClosed => _closed;

  /// 当前引擎已累计估算分配的堆内存字节数
  int get allocatedBytes => _ls.allocatedBytes;

  LuaEngine({
    required this.context,
    required this.delegate,
    this.instructionBudget = defaultInstructionBudget,
    this.memoryBudget = defaultMemoryBudget,
    this.databaseFactory,
    this.onCallbackError,
  }) {
    _ls = LuaState.newState();
    _ls.openLibs();
    _registerSecuritySandbox();
    _registerHostApis();
    _ls.setMemoryBudget(memoryBudget);
  }

  /// 封禁具有潜在安全风险的 Lua 标准库。
  ///
  /// lua_dardo 的 openLibs 会注册 base/table/string/math/os/package：
  /// `os.execute`/`os.remove`/`io` 文件操作可执行任意系统命令与读写任意文件，
  /// `require`/`dofile`/`loadfile` 可从磁盘加载任意脚本，`debug`/`package`
  /// 可触达虚拟机内部。全部置 nil 以彻底封堵沙箱逃逸面。
  ///
  /// `load`/`loadstring`/`string.dump` 一并封禁：lua_dardo 的 `load` 实现
  /// 忽略 mode 参数、始终接受二进制块，无法限制为仅文本（mode='t'），
  /// 保留它们即可加载手工构造的字节码绕过全部源码层校验。
  void _registerSecuritySandbox() {
    for (final lib in [
      'os',
      'io',
      'debug',
      'package',
      'require',
      'dofile',
      'loadfile',
      'load',
      'loadstring',
    ]) {
      _ls.pushNil();
      _ls.setGlobal(lib);
    }
    // string.dump 可将函数序列化为字节码供 load 回灌，单独摘除该字段
    if (_ls.getGlobal('string') == LuaType.luaTable) {
      _ls.pushNil();
      _ls.setField(-2, 'dump');
    }
    _ls.pop(1);
  }

  /// 注册所有受白名单权限控制的宿主 API
  void _registerHostApis() {
    _callbacks = LuaCallbackInvoker(
      _ls,
      instructionBudget,
      onError: (err) {
        context.logger.e('Lua Callback Execution Error: $err');
        onCallbackError?.call(err);
      },
    );
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
    SystemApi.bind(_ls, context, delegate, _callbacks!);
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
    _databaseApi = DatabaseApi(databaseFactory: databaseFactory);
    _databaseApi!.bindInstance(_ls, context, _callbacks!);
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
    _databaseApi?.dispose();
    _callbacks?.clear();
  }
}
