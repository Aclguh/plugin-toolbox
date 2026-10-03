

import 'lua_aux_lib.dart';
import 'lua_basic_api.dart';
import '../state/lua_state_impl.dart';


const luaMinStack = 20;
const luaMaxStack = 1000000;
const luaRegistryIndex = -luaMaxStack - 1000;
const luaMultret = -1;
const luaRidxGlobals = 2;

const luaMaxInteger = 1<<63 - 1;
const luaMinInteger = -1 << 63;

abstract class LuaState extends LuaBasicAPI implements LuaAuxLib{

  static LuaState newState(){
    return LuaStateImpl();
  }

  /// 设置指令数预算 (本地分支扩展):
  /// [maxInstructions] 为之后每次 Lua 闭包执行允许的最大虚拟机指令条数,
  /// 超限将抛出异常 (会被 pCall 捕获为 luaErrRun); 传 null 表示不限制。
  /// 调用后已执行计数同时归零。
  void setInstructionBudget(int? maxInstructions);
}
