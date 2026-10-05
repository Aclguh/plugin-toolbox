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
import 'lua_callback_invoker.dart';

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
    SystemApi.bind(_ls, delegate);
    HapticApi.bind(_ls, delegate);
    UiApi.bind(_ls, delegate);
    ShareApi.bind(_ls, delegate);
    MediaApi.bind(_ls, context, delegate, _callbacks!, writeState);
    FsApi.bind(_ls, context);
    CryptoApi.bind(_ls);
    RegexApi.bind(_ls);
    ColorApi.bind(_ls);
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

  void _pushValue(dynamic val, [Set<Object?>? visited]) {
    // 循环引用检测：自引用集合若不拦截将在递归压栈时栈溢出
    if (val is Map || val is List) {
      final seen = visited ??= <Object?>{};
      if (seen.contains(val)) {
        throw Exception('不支持将包含循环引用的集合转换为 Lua 值');
      }
      seen.add(val);
    }

    if (val == null) {
      _ls.pushNil();
    } else if (val is bool) {
      _ls.pushBoolean(val);
    } else if (val is int) {
      _ls.pushInteger(val);
    } else if (val is double) {
      _ls.pushNumber(val);
    } else if (val is String) {
      _ls.pushString(val);
    } else if (val is Map) {
      _ls.newTable();
      val.forEach((k, v) {
        _ls.pushString(k.toString());
        _pushValue(v, visited);
        _ls.setTable(-3);
      });
    } else if (val is List) {
      _ls.newTable();
      for (int i = 0; i < val.length; i++) {
        _ls.pushInteger(i + 1);
        _pushValue(val[i], visited);
        _ls.setTable(-3);
      }
    } else {
      _ls.pushString(val.toString());
    }

    visited?.remove(val);
  }

  dynamic _popValue() {
    final type = _ls.type(-1);
    dynamic result;
    switch (type) {
      case LuaType.luaNil:
        result = null;
        break;
      case LuaType.luaBoolean:
        result = _ls.toBoolean(-1);
        break;
      case LuaType.luaNumber:
        result = _ls.isInteger(-1) ? _ls.toInteger(-1) : _ls.toNumber(-1);
        break;
      case LuaType.luaString:
        result = _ls.toStr(-1);
        break;
      case LuaType.luaTable:
        result = _readTable(-1);
        break;
      default:
        result = null;
    }
    _ls.pop(1);
    return result;
  }

  dynamic _readTable(int idx) {
    final rawEntries = <dynamic, dynamic>{};
    _ls.pushNil();
    while (_ls.next(idx < 0 ? idx - 1 : idx)) {
      final dynamic key = _ls.isInteger(-2)
          ? _ls.toInteger(-2)
          : (_ls.toStr(-2) ?? _ls.toInteger(-2).toString());
      final val = _readCurrentValue();
      rawEntries[key] = val;
      _ls.pop(1);
    }

    if (rawEntries.isEmpty) {
      return <String, dynamic>{};
    }

    // 检查是否为从 1 开始、连续到 N 的纯整数索引表（Lua 数组特征）
    bool isSequentialArray = true;
    for (int i = 1; i <= rawEntries.length; i++) {
      if (!rawEntries.containsKey(i)) {
        isSequentialArray = false;
        break;
      }
    }

    if (isSequentialArray) {
      final list = List<dynamic>.filled(rawEntries.length, null, growable: true);
      for (int i = 1; i <= rawEntries.length; i++) {
        list[i - 1] = rawEntries[i];
      }
      return list;
    }

    // 否则作为 Map<String, dynamic> 返回
    final map = <String, dynamic>{};
    for (final entry in rawEntries.entries) {
      map[entry.key.toString()] = entry.value;
    }
    return map;
  }

  dynamic _readCurrentValue() {
    final type = _ls.type(-1);
    switch (type) {
      case LuaType.luaNil:
        return null;
      case LuaType.luaBoolean:
        return _ls.toBoolean(-1);
      case LuaType.luaNumber:
        return _ls.isInteger(-1) ? _ls.toInteger(-1) : _ls.toNumber(-1);
      case LuaType.luaString:
        return _ls.toStr(-1);
      case LuaType.luaTable:
        return _readTable(-1);
      default:
        return null;
    }
  }

  /// 关闭引擎并释放所持有的注册表回调引用与资源。
  /// 关闭后再调用执行操作将抛出 [StateError]。
  void close() {
    if (_closed) return;
    _closed = true;
    _timerApi?.dispose(_callbacks);
    _callbacks?.clear();
  }
}
