import 'dart:async';
import 'package:lua_dardo/lua.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';
import 'api/state_api.dart';
import 'api/clipboard_api.dart';
import 'api/storage_api.dart';
import 'api/network_api.dart';
import 'api/dialog_api.dart';
import 'api/codec_api.dart';
import 'api/hash_api.dart';
import 'api/util_api.dart';

/// 插件与宿主 UI 的双向交互委托
abstract class LuaHostDelegate {
  void onStateChanged(String key, dynamic value);
  dynamic getState(String key);
  Map<String, dynamic> getAllStates();
  void showToast(String message);
  Future<void> showAlert(String title, String message);
  Future<bool> showConfirm(String title, String message);
}

class LuaEngine {
  final PluginContext context;
  final LuaHostDelegate delegate;
  late final LuaState _ls;

  LuaEngine({
    required this.context,
    required this.delegate,
  }) {
    _ls = LuaState.newState();
    _ls.openLibs();
    _registerSecuritySandbox();
    _registerHostApis();
  }

  /// 禁用具有潜在安全风险的 Lua 原生库函数
  void _registerSecuritySandbox() {
    // 禁用危险的 os, io, package, debug 库中可能导致越权的函数
    _ls.pushNil();
    _ls.setGlobal('dofile');
    _ls.pushNil();
    _ls.setGlobal('loadfile');
  }

  /// 注册所有受白名单权限控制的宿主 API
  void _registerHostApis() {
    StateApi.bind(_ls, delegate);
    ClipboardApi.bind(_ls, context);
    StorageApi.bind(_ls, context);
    NetworkApi.bind(_ls, context);
    DialogApi.bind(_ls, delegate);
    CodecApi.bind(_ls);
    HashApi.bind(_ls);
    UtilApi.bind(_ls);
  }

  /// 执行 Lua 源代码字符串
  void loadAndExecute(String scriptContent) {
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
    final type = _ls.getGlobal(funcName);
    if (type != LuaType.luaFunction) {
      _ls.pop(1);
      return null;
    }

    for (final arg in args) {
      _pushValue(arg);
    }

    final status = _ls.pCall(args.length, 1, 0);
    if (status != ThreadStatus.luaOk) {
      final err = _ls.toStr(-1) ?? 'Error in function $funcName';
      _ls.pop(1);
      throw Exception('调用 Lua 函数 [$funcName] 失败: $err');
    }

    final res = _popValue();
    return res;
  }

  void _pushValue(dynamic val) {
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
        _pushValue(v);
        _ls.setTable(-3);
      });
    } else if (val is List) {
      _ls.newTable();
      for (int i = 0; i < val.length; i++) {
        _ls.pushInteger(i + 1);
        _pushValue(val[i]);
        _ls.setTable(-3);
      }
    } else {
      _ls.pushString(val.toString());
    }
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

  Map<String, dynamic> _readTable(int idx) {
    final map = <String, dynamic>{};
    _ls.pushNil();
    while (_ls.next(idx < 0 ? idx - 1 : idx)) {
      final key = _ls.toStr(-2) ?? _ls.toInteger(-2).toString();
      final val = _readCurrentValue();
      map[key] = val;
      _ls.pop(1);
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
      default:
        return null;
    }
  }

  void close() {
    // LuaState in lua_dardo is managed by Dart GC
  }
}
