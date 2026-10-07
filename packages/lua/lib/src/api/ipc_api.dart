import 'package:lua_dardo/lua.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';

import '../lua_callback_invoker.dart';
import '../lua_engine.dart';
import '../lua_value_codec.dart';

/// `plugin` / `ipc` — 跨插件服务调用与管道通信宿主 API。
class IpcApi {
  static void bind(
    LuaState ls,
    PluginContext context,
    LuaHostDelegate delegate,
    LuaCallbackInvoker callbacks,
  ) {
    ls.newTable();

    void checkPermission(LuaState ls) {
      if (!context.hasPermission(PluginPermission.ipc)) {
        ls.error2('权限不足: 插件未声明 ipc 权限');
      }
    }

    // plugin.call(targetPluginId, functionName [, args | callback, callback])
    ls.pushDartFunction((ls) {
      checkPermission(ls);
      final targetPluginId = ls.checkString(1) ?? '';
      final functionName = ls.checkString(2) ?? '';
      dynamic args;
      int? cbRef;

      if (ls.type(3) == LuaType.luaFunction) {
        cbRef = callbacks.ref(3);
      } else if (ls.type(3) != LuaType.luaNil && ls.type(3) != LuaType.luaNone) {
        ls.pushValue(3);
        args = LuaValueCodec.pop(ls);
        if (ls.type(4) == LuaType.luaFunction) {
          cbRef = callbacks.ref(4);
        }
      }

      PluginIpcBroker.instance
          .call(
        callerPluginId: context.pluginId,
        targetPluginId: targetPluginId,
        functionName: functionName,
        args: args,
      )
          .then((res) {
        if (cbRef != null) {
          callbacks.invokeAndRelease(cbRef, [res]);
        }
      }).catchError((Object e) {
        if (cbRef != null) {
          callbacks.invokeAndRelease(cbRef, [
            {'ok': false, 'error': e.toString()}
          ]);
        }
      });
      return 0;
    });
    ls.setField(-2, 'call');

    // plugin.export(functionName, callback)
    // 导出当前插件的处理函数供其他插件调用
    ls.pushDartFunction((ls) {
      checkPermission(ls);
      final functionName = ls.checkString(1) ?? '';
      final cbRef = callbacks.ref(2);

      if (cbRef != null) {
        PluginIpcBroker.instance.registerService(
          context.pluginId,
          functionName,
          (args) async {
            // 调用 Lua 侧的处理函数
            final result = callbacks.invokeWithResult(cbRef, [args]);
            return result;
          },
        );
      }
      return 0;
    });
    ls.setField(-2, 'export');

    // plugin.open(targetPluginId [, initialDataTable [, callback]])
    ls.pushDartFunction((ls) {
      checkPermission(ls);
      final targetPluginId = ls.checkString(1) ?? '';
      Map<String, dynamic>? initialData;
      int? cbRef;

      if (ls.type(2) == LuaType.luaFunction) {
        cbRef = callbacks.ref(2);
      } else if (ls.type(2) == LuaType.luaTable) {
        ls.pushValue(2);
        final raw = LuaValueCodec.pop(ls);
        if (raw is Map) initialData = raw.cast<String, dynamic>();
        if (ls.type(3) == LuaType.luaFunction) {
          cbRef = callbacks.ref(3);
        }
      }

      delegate
          .openPlugin(targetPluginId, initialData: initialData)
          .then((opened) {
        if (cbRef != null) {
          callbacks.invokeAndRelease(cbRef, [
            {'ok': opened, if (!opened) 'error': '无法打开目标插件'}
          ]);
        }
      }).catchError((Object e) {
        if (cbRef != null) {
          callbacks.invokeAndRelease(cbRef, [
            {'ok': false, 'error': e.toString()}
          ]);
        }
      });
      return 0;
    });
    ls.setField(-2, 'open');

    // 绑定至全局 plugin
    ls.setGlobal('plugin');
  }
}
