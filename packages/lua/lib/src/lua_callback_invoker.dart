import 'package:lua_dardo/lua.dart';

/// Lua 异步回调调用器。
///
/// 网络/存储/对话框等异步操作完成时，Lua 同步栈早已退出，需要"稍后再入
/// 虚拟机"调用脚本登记的回调函数。宿主事件循环空闲时才可能触发这些回调
/// （Lua 执行本身在主 isolate 上是同步的），因此此处再入是安全的；
/// 每次再入前重置指令数预算，避免回调与主流程共享计数导致误伤。
class LuaCallbackInvoker {
  final LuaState _ls;
  final int _instructionBudget;

  LuaCallbackInvoker(this._ls, this._instructionBudget);

  /// 登记栈上 [stackIdx] 位置的函数供稍后调用；非函数参数返回 null
  int? ref(int stackIdx) {
    if (_ls.type(stackIdx) != LuaType.luaFunction) return null;
    _ls.pushValue(stackIdx);
    return _ls.ref(luaRegistryIndex);
  }

  /// 调用 [ref] 登记的回调并释放登记，[args] 为可安全跨栈的基础类型值。
  /// 回调内部的 Lua 错误被降级吞掉，不允许逃逸到宿主事件循环。
  void invokeAndRelease(int ref, List<Object?> args) {
    _ls.rawGetI(luaRegistryIndex, ref);
    _ls.unRef(luaRegistryIndex, ref);
    _invokeTop(args);
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

  void _pushArg(Object? val) {
    if (val == null) {
      _ls.pushNil();
    } else if (val is bool) {
      _ls.pushBoolean(val);
    } else if (val is int) {
      _ls.pushInteger(val);
    } else if (val is double) {
      _ls.pushNumber(val);
    } else {
      _ls.pushString(val.toString());
    }
  }
}
