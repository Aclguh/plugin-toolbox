import 'dart:convert';
import 'dart:io';
import 'package:lua_dardo/lua.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';
import 'package:http/http.dart' as http;
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
import 'api/i18n_api.dart';
import 'delegates/domain_delegates.dart';
import 'lua_callback_invoker.dart';
import 'lua_disposable.dart';
import 'lua_value_codec.dart';

export 'delegates/domain_delegates.dart';
export 'api/plugin_database.dart';
export 'lua_disposable.dart';

/// 安全隔离的 Lua 运行时引擎，提供宿主 API 绑定注入与指令数死循环预算保护
class LuaEngine {
  final PluginContext context;
  final LuaHostDelegate delegate;

  /// 单次 Lua 闭包执行允许的最大虚拟机指令条数，防止 `while true do end`
  /// 类死循环永久冻结宿主主线程；超限抛出异常并由 pCall 降级为执行错误。
  static const int defaultInstructionBudget =
      ToolboxConstants.defaultInstructionBudget;

  /// 单个 Lua 虚拟机实例允许的最大堆内存预算（字节），防止巨型 Table 或长字符串
  /// 耗尽宿主内存造成 OOM 强杀。默认 32MB。
  static const int defaultMemoryBudget = ToolboxConstants.defaultMemoryBudget;

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
  final DisposableTracker _disposableTracker = DisposableTracker();
  final Map<String, void Function()> _lazyModuleBinders = {};
  final Set<String> _boundModules = {};
  bool _closed = false;

  /// 集中资源生命周期追踪器
  DisposableTracker get disposables => _disposableTracker;

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
        context.recordLog('[ERROR] $err');
        context.logger.e('Lua Callback Execution Error: $err');
        onCallbackError?.call(err);
      },
    );

    // 重定向 Lua print 函数至 context.recordLog 与 logger
    _ls.pushDartFunction((ls) {
      final top = ls.getTop();
      final buf = StringBuffer();
      for (var i = 1; i <= top; i++) {
        if (i > 1) buf.write('\t');
        final type = ls.type(i);
        if (type == LuaType.luaString || type == LuaType.luaNumber) {
          buf.write(ls.toStr(i) ?? '');
        } else if (type == LuaType.luaBoolean) {
          buf.write(ls.toBoolean(i));
        } else if (type == LuaType.luaNil) {
          buf.write('nil');
        } else {
          buf.write(ls.typeName(type));
        }
      }
      final msg = buf.toString();
      context.recordLog(msg);
      context.logger.i('[Lua print] $msg');
      return 0;
    });
    _ls.setGlobal('print');

    // 初始化沙箱模块缓存表 (模拟 package.loaded)
    _ls.newTable();
    _ls.setGlobal('__loaded_modules');

    // 注入沙箱受限的虚拟 require 模块加载器
    _ls.pushDartFunction((ls) {
      final moduleName = ls.checkString(1);
      if (moduleName == null || moduleName.trim().isEmpty) {
        ls.error2('require 缺少有效的模块名参数');
        return 0;
      }

      final rawName = moduleName.trim();
      if (rawName.contains('..') || SandboxPath.isAbsolutePath(rawName)) {
        ls.error2('安全策略拦截: 非法的模块路径 [$moduleName]');
        return 0;
      }

      final rootDir = context.rootDir;
      if (rootDir == null) {
        ls.error2('模块加载失败: 当前插件无本地沙箱根目录');
        return 0;
      }

      var relPath = moduleName.trim();
      if (!relPath.endsWith('.lua')) {
        relPath = '${relPath.replaceAll('.', '/')}.lua';
      }
      relPath = relPath.replaceAll(r'\', '/');
      while (relPath.startsWith('/')) {
        relPath = relPath.substring(1);
      }
      final canonicalKey = relPath.substring(0, relPath.length - '.lua'.length);

      // 路径穿越与越权拦截：严格限定于沙箱内部
      if (!SandboxPath.isSafeSubpath(rootDir.path, relPath)) {
        ls.error2('安全策略拦截: 非法的模块路径 [$moduleName]');
        return 0;
      }

      // 检查缓存 (以规范化路径为统一 key)
      ls.getGlobal('__loaded_modules');
      ls.getField(-1, canonicalKey);
      if (!ls.isNil(-1)) {
        ls.remove(-2);
        return 1;
      }
      ls.pop(1);

      final targetFile = File('${rootDir.path}/$relPath');
      if (!targetFile.existsSync()) {
        ls.pop(1);
        ls.error2('模块未找到: [$moduleName] (文件不存在: $relPath)');
        return 0;
      }

      final bytes = targetFile.readAsBytesSync();
      if (SandboxPath.isLuaBytecode(bytes)) {
        ls.pop(1);
        ls.error2('安全策略拦截: 模块禁止使用预编译 Lua 字节码 [$moduleName]');
        return 0;
      }

      final script = utf8.decode(bytes);

      // 预先写入 true 防范循环依赖死递归
      ls.pushBoolean(true);
      ls.setField(-2, canonicalKey);

      ls.setInstructionBudget(instructionBudget);
      final loadStatus = ls.loadString(script);
      if (loadStatus != ThreadStatus.luaOk) {
        final err = ls.toStr(-1) ?? 'Syntax error';
        ls.pop(2);
        ls.error2('模块编译失败 [$moduleName]: $err');
        return 0;
      }

      final pcallStatus = ls.pCall(0, 1, 0);
      if (pcallStatus != ThreadStatus.luaOk) {
        final err = ls.toStr(-1) ?? 'Runtime error';
        ls.pop(2);
        ls.error2('模块执行错误 [$moduleName]: $err');
        return 0;
      }

      if (!ls.isNil(-1)) {
        ls.pushValue(-1);
        ls.setField(-3, canonicalKey);
      } else {
        ls.pop(1);
        ls.pushBoolean(true);
      }

      ls.remove(-2);
      return 1;
    });
    _ls.setGlobal('require');

    void writeState(String key, dynamic value) =>
        delegate.onStateChanged(key, value);

    // 核心高频 API 立即注入
    _timerApi = TimerApi();
    _timerApi!.bind(_ls, _callbacks!);
    _disposableTracker.addCallback(() => _timerApi?.dispose(_callbacks));

    StateApi.bind(_ls, delegate);
    _boundModules.add('state');
    ClipboardApi.bind(_ls, context, delegate, _callbacks!, writeState);
    _boundModules.add('clipboard');
    CodecApi.bind(_ls);
    _boundModules.add('codec');
    JsonApi.bind(_ls);
    _boundModules.add('json');
    UtilApi.bind(_ls);
    _boundModules.add('util');
    DialogApi.bind(_ls, delegate, _callbacks!);
    _boundModules.add('dialog');
    UiApi.bind(_ls, delegate);
    _boundModules.add('ui');
    HapticApi.bind(_ls, delegate);
    _boundModules.add('haptic');

    // 注册低频/重型 API 的懒加载映射表
    _lazyModuleBinders['storage'] = () {
      StorageApi.bind(_ls, context, _callbacks!, writeState);
    };
    _lazyModuleBinders['network'] = () {
      final networkClient = http.Client();
      NetworkApi.bind(
          _ls, context, _callbacks!, writeState, delegate, networkClient);
      _disposableTracker.addCallback(() => networkClient.close());
    };
    _lazyModuleBinders['hash'] = () => HashApi.bind(_ls);
    _lazyModuleBinders['system'] =
        () => SystemApi.bind(_ls, context, delegate, _callbacks!);
    _lazyModuleBinders['share'] =
        () => ShareApi.bind(_ls, delegate, context, _callbacks!);
    _lazyModuleBinders['media'] =
        () => MediaApi.bind(_ls, context, delegate, _callbacks!, writeState);
    _lazyModuleBinders['fs'] =
        () => FsApi.bind(_ls, context, delegate, _callbacks!);
    _lazyModuleBinders['crypto'] = () => CryptoApi.bind(_ls);
    _lazyModuleBinders['regex'] = () => RegexApi.bind(_ls);
    _lazyModuleBinders['color'] = () => ColorApi.bind(_ls);
    _lazyModuleBinders['archive'] = () => ArchiveApi.bind(_ls, context);
    _lazyModuleBinders['document'] = () => DocumentApi.bind(_ls);
    _lazyModuleBinders['torch'] =
        () => TorchApi.bind(_ls, context, delegate, _callbacks!);
    _lazyModuleBinders['qrcode'] = () => QrcodeApi.bind(_ls);
    _lazyModuleBinders['camera'] =
        () => CameraApi.bind(_ls, context, delegate, _callbacks!);
    _lazyModuleBinders['vision'] =
        () => VisionApi.bind(_ls, context, delegate, _callbacks!);
    _lazyModuleBinders['sensor'] = () {
      _sensorApi = SensorApi();
      _sensorApi!.bind(_ls, context, delegate, _callbacks!);
      _disposableTracker
          .addCallback(() => _sensorApi?.dispose(delegate, _callbacks!));
    };
    _lazyModuleBinders['image'] =
        () => ImageApi.bind(_ls, context, delegate, _callbacks!);
    _lazyModuleBinders['notification'] =
        () => NotificationApi.bind(_ls, context, delegate, _callbacks!);
    _lazyModuleBinders['audio'] = () {
      AudioApi.bind(_ls, context, delegate, _callbacks!);
      _disposableTracker.addCallback(() => delegate.stopAudio());
    };
    _lazyModuleBinders['socket'] = () {
      _socketApi = SocketApi();
      _socketApi!.bind(_ls, context, _callbacks!);
      _disposableTracker.addCallback(() => _socketApi?.dispose(_callbacks));
    };
    _lazyModuleBinders['websocket'] = () {
      _webSocketApi = WebSocketApi();
      _webSocketApi!.bind(_ls, context, _callbacks!);
      _disposableTracker.addCallback(() => _webSocketApi?.dispose(_callbacks));
    };
    _lazyModuleBinders['biometrics'] =
        () => BiometricsApi.bind(_ls, context, delegate, _callbacks!);
    _lazyModuleBinders['task'] = () => TaskApi.bind(_ls, context, _callbacks!);
    _lazyModuleBinders['screen'] = () {
      ScreenApi.bind(_ls, context, delegate, _callbacks!);
      _disposableTracker.addCallback(() => delegate.setKeepScreenOn(false));
      _disposableTracker.addCallback(() => delegate.resetBrightness());
    };
    _lazyModuleBinders['location'] =
        () => LocationApi.bind(_ls, context, delegate, _callbacks!);
    _lazyModuleBinders['nfc'] =
        () => NfcApi.bind(_ls, context, delegate, _callbacks!);
    _lazyModuleBinders['bluetooth'] = () {
      BluetoothApi.bind(_ls, context, delegate, _callbacks!);
      _disposableTracker.addCallback(() => delegate.stopBluetoothScan());
    };
    void bindDatabase() {
      _databaseApi = DatabaseApi(databaseFactory: databaseFactory);
      _databaseApi!.bindInstance(_ls, context, _callbacks!);
      _disposableTracker.addCallback(() => _databaseApi?.dispose());
    }

    _lazyModuleBinders['db'] = bindDatabase;
    _lazyModuleBinders['database'] = bindDatabase;

    _lazyModuleBinders['ai'] =
        () => AiApi.bind(_ls, context, delegate, _callbacks!);

    void bindIpc() {
      IpcApi.bind(_ls, context, delegate, _callbacks!);
      _disposableTracker.addCallback(
          () => PluginIpcBroker.instance.unregisterService(context.pluginId));
    }

    _lazyModuleBinders['plugin'] = bindIpc;
    _lazyModuleBinders['ipc'] = bindIpc;
    _lazyModuleBinders['i18n'] = () => I18nApi.bind(_ls, context);

    // 注入底层按需绑定桥接函数
    _ls.pushDartFunction((ls) {
      final modName = ls.checkString(1);
      if (modName != null) {
        _bindModule(modName);
      }
      return 0;
    });
    _ls.setGlobal('__bind_host_module');

    // 在 Lua 全局表 _G 安装元表，按需懒加载未绑定的宿主模块
    final lazyKeysLua =
        _lazyModuleBinders.keys.map((k) => '["$k"]=true').join(',');
    _ls.doString('''
local __lazy_keys = {$lazyKeysLua}
setmetatable(_G, {
  __index = function(t, key)
    if __lazy_keys[key] then
      __bind_host_module(key)
      return rawget(t, key)
    end
    return nil
  end
})
''');
  }

  /// 显式全量绑定所有宿主 API（主要用于离线静态分析或需要预先穷举全局表的场景）
  void bindAll() {
    final modules = _lazyModuleBinders.keys.toList();
    for (final mod in modules) {
      _bindModule(mod);
    }
  }

  /// 检查指定宿主模块是否已被实际绑定并驻留于全局环境
  bool isModuleBound(String name) => _boundModules.contains(name);

  void _bindModule(String name) {
    if (_boundModules.contains(name)) return;
    _boundModules.add(name);
    final binder = _lazyModuleBinders[name];
    if (binder != null) {
      binder();
    }
  }

  /// 校验脚本字符串是否以 Lua 预编译字节码魔数 (\x1bLua) 开头
  static bool isLuaBytecodeString(String script) {
    if (script.length >= 4) {
      return script.codeUnitAt(0) == 0x1B &&
          script.codeUnitAt(1) == 0x4C &&
          script.codeUnitAt(2) == 0x75 &&
          script.codeUnitAt(3) == 0x61;
    }
    return false;
  }

  /// 执行 Lua 源代码字符串
  void loadAndExecute(String scriptContent) {
    if (_closed) {
      throw StateError('Cannot use closed LuaEngine');
    }
    if (isLuaBytecodeString(scriptContent)) {
      throw const FormatException('安全策略拦截: 禁止执行预编译 Lua 字节码，必须为源码文本');
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
    _disposableTracker.disposeAll();
    _callbacks?.clear();
  }
}
