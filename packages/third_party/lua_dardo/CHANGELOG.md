## 0.0.5+toolbox.1 (PluginToolbox 本地维护分支)

- 在 `LuaStateImpl._runLuaClosure` 虚拟机执行循环中加入指令数预算检查:
  通过 `LuaState.setInstructionBudget(int?)` 设置每次闭包执行的最大指令条数,
  超限抛出异常 (pCall 捕获为 luaErrRun), 用于宿主侧防止插件脚本死循环冻结应用。
- 同步调整 SDK 约束至 `^3.0.0` 以匹配宿主 Monorepo。
- 上游: https://github.com/arcticfox1919/LuaDardo (Apache-2.0), 版本 0.0.5。

## 0.0.5
* Fix issues [#10](https://github.com/arcticfox1919/LuaDardo/issues/10)
* Fix warning

## 0.0.4
* Upgrade null safety

## 0.0.3
* Fix the bug of the table constructor
* Add auxiliary API for reference(`ref`/`unRef`)

## 0.0.2
* Add Lua userdata support
* Fix lexical analysis BUG

## 0.0.1
* A full lua virtual machine
* Support some standard libraries, e.g. String, Math, etc.
* Experimental nature only, not yet fully tested