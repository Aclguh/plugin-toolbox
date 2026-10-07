import 'package:lua_dardo/lua.dart';
import 'lua_value_codec.dart';

/// Lua 异步回调调用器。
///
/// 网络/存储/对话框等异步操作完成时，Lua 同步栈早已退出，需要"稍后再入
/// 虚拟机"调用脚本登记的回调函数。宿主事件循环空闲时才可能触发这些回调
/// （Lua 执行本身在主 isolate 上是同步的），因此此处再入是安全的；
/// 每次再入前重置指令数预算，避免回调与主流程共享计数导致误伤。
class LuaCallbackInvoker {
  final LuaState _ls;
  final int _instructionBudget;
  final Set<int> _activeRefs = {};

  LuaCallbackInvoker(this._ls, this._instructionBudget);

  /// 登记栈上 [stackIdx] 位置的函数供稍后调用；非函数参数返回 null
  int? ref(int stackIdx) {
    if (_ls.type(stackIdx) != LuaType.luaFunction) return null;
    _ls.pushValue(stackIdx);
    final r = _ls.ref(luaRegistryIndex);
    _activeRefs.add(r);
    return r;
  }

  /// 调用 [ref] 登记的回调并释放登记，[args] 为可安全跨栈的基础类型值或集合。
  /// 回调内部的 Lua 错误被降级吞掉，不允许逃逸到宿主事件循环。
  void invokeAndRelease(int ref, List<Object?> args) {
    if (!_activeRefs.remove(ref)) return;
    _ls.rawGetI(luaRegistryIndex, ref);
    _ls.unRef(luaRegistryIndex, ref);
    _invokeTop(args);
  }

  /// 仅调用 [ref] 登记的回调而不释放登记（适用于 setInterval 等持续周期触发场景）
  void invoke(int ref, List<Object?> args) {
    if (!_activeRefs.contains(ref)) return;
    _ls.rawGetI(luaRegistryIndex, ref);
    _invokeTop(args);
  }

  /// 调用 [ref] 登记的回调函数并获取 1 个返回值 (适用于 IPC / RPC 等服务调用场景)
  dynamic invokeWithResult(int ref, List<Object?> args) {
    if (!_activeRefs.contains(ref)) return null;
    _ls.rawGetI(luaRegistryIndex, ref);
    for (final arg in args) {
      _pushArg(arg);
    }
    _ls.setInstructionBudget(_instructionBudget);
    final status = _ls.pCall(args.length, 1, 0);
    if (status != ThreadStatus.luaOk) {
      _ls.pop(1);
      return null;
    }
    return LuaValueCodec.pop(_ls);
  }

  /// 显式注销并释放 [ref] 登记项
  void release(int ref) {
    if (_activeRefs.remove(ref)) {
      _ls.unRef(luaRegistryIndex, ref);
    }
  }

  /// 释放所有注册表中的未完成回调引用，切断 Dart -> Lua 引用链，加速 GC
  void clear() {
    for (final r in _activeRefs) {
      _ls.unRef(luaRegistryIndex, r);
    }
    _activeRefs.clear();
  }

  /// 调用 Lua 全局函数 [funcName]（若脚本未定义则静默跳过）
  void invokeGlobal(String funcName, List<Object?> args) {
    final type = _ls.getGlobal(funcName);
    if (type != LuaType.luaFunction) {
      _ls.pop(1);
      return;
    }
    _invokeTop(args);
  }

  void _invokeTop(List<Object?> args) {
    for (final arg in args) {
      _pushArg(arg);
    }
    _ls.setInstructionBudget(_instructionBudget);
    final status = _ls.pCall(args.length, 0, 0);
    if (status != ThreadStatus.luaOk) {
      // pCall 失败时会压入错误信息，出栈以保持栈平衡
      _ls.pop(1);
    }
  }

  void _pushArg(Object? val, [Set<Object?>? visited]) {
    if (val is Map || val is List) {
      final seen = visited ??= <Object?>{};
      if (seen.contains(val)) {
        _ls.pushNil();
        return;
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
        _pushArg(v, visited);
        _ls.setTable(-3);
      });
    } else if (val is List) {
      _ls.newTable();
      for (int i = 0; i < val.length; i++) {
        _ls.pushInteger(i + 1);
        _pushArg(val[i], visited);
        _ls.setTable(-3);
      }
    } else {
      _ls.pushString(val.toString());
    }

    visited?.remove(val);
  }
}
