import 'dart:async';

import 'package:lua_dardo/lua.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';

import '../lua_callback_invoker.dart';

class StorageApi {
  /// [writeState] 即 LuaHostDelegate.onStateChanged：未提供回调时，
  /// 异步结果降级写入插件状态供脚本后续读取。
  static void bind(
    LuaState ls,
    PluginContext context,
    LuaCallbackInvoker callbacks,
    void Function(String key, dynamic value) writeState,
  ) {
    ls.newTable();

    // storage.set(key, value)
    ls.pushDartFunction((ls) {
      if (!context.hasPermission(PluginPermission.storage)) {
        ls.error2('权限不足: 插件未声明 storage 权限');
        return 0;
      }
      final key = ls.checkString(1) ?? '';
      final val = ls.checkString(2) ?? '';
      unawaited(context.storage.setString(key, val));
      return 0;
    });
    ls.setField(-2, 'set');

    // storage.get(key [, callback])
    // 读取为异步操作，无法在同步 Lua 栈中直接返回值：
    // 传入回调函数则异步携带存储值回调，否则结果写入状态 __storage_value
    ls.pushDartFunction((ls) {
      if (!context.hasPermission(PluginPermission.storage)) {
        ls.error2('权限不足: 插件未声明 storage 权限');
        return 0;
      }
      final key = ls.checkString(1) ?? '';
      final cbRef = callbacks.ref(2);
      unawaited(
        context.storage.getString(key).then((value) {
          if (cbRef != null) {
            callbacks.invokeAndRelease(cbRef, [value]);
          } else if (value != null) {
            writeState('__storage_value', value);
          }
        }).catchError((Object e) {
          writeState('__storage_error', e.toString());
          if (cbRef != null) {
            callbacks.invokeAndRelease(cbRef, [null]);
          }
        }),
      );
      return 0;
    });
    ls.setField(-2, 'get');

    // storage.remove(key)
    ls.pushDartFunction((ls) {
      if (!context.hasPermission(PluginPermission.storage)) {
        ls.error2('权限不足: 插件未声明 storage 权限');
        return 0;
      }
      final key = ls.checkString(1) ?? '';
      unawaited(context.storage.remove(key));
      return 0;
    });
    ls.setField(-2, 'remove');

    ls.setGlobal('storage');
  }
}
