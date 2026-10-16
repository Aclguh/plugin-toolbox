import 'dart:async';

import 'package:lua_dardo/lua.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';

import '../lua_callback_invoker.dart';
import '../lua_value_codec.dart';

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

    // storage.set(key, value [, callback])
    ls.pushDartFunction((ls) {
      if (!context.hasPermission(PluginPermission.storage)) {
        ls.error2('权限不足: 插件未声明 storage 权限');
        return 0;
      }
      final key = ls.checkString(1) ?? '';
      dynamic val;
      final type = ls.type(2);
      if (type == LuaType.luaTable) {
        val = LuaValueCodec.readTable(ls, 2);
      } else if (type == LuaType.luaBoolean) {
        val = ls.toBoolean(2);
      } else if (type == LuaType.luaNumber) {
        val = ls.isInteger(2) ? ls.toInteger(2) : ls.toNumber(2);
      } else if (type == LuaType.luaString) {
        val = ls.toStr(2);
      } else if (type == LuaType.luaNil) {
        val = null;
      }
      final cbRef = callbacks.ref(3);
      final future = val == null
          ? context.storage.remove(key)
          : context.storage.setValue(key, val);

      if (cbRef != null) {
        unawaited(
          future.then((ok) {
            callbacks.invokeAndRelease(cbRef, [ok]);
          }).catchError((Object e) {
            callbacks.invokeAndRelease(cbRef, [false, e.toString()]);
          }),
        );
      } else {
        unawaited(future);
      }
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
        context.storage.getValue(key).then((value) {
          if (cbRef != null) {
            callbacks.invokeAndRelease(cbRef, [value]);
          } else if (value != null) {
            writeState('__storage_value', value);
          }
        }).catchError((Object e) {
          writeState('__storage_error', e.toString());
          if (cbRef != null) {
            callbacks.invokeAndRelease(cbRef, [null, e.toString()]);
          }
        }),
      );
      return 0;
    });
    ls.setField(-2, 'get');

    // storage.remove(key [, callback])
    ls.pushDartFunction((ls) {
      if (!context.hasPermission(PluginPermission.storage)) {
        ls.error2('权限不足: 插件未声明 storage 权限');
        return 0;
      }
      final key = ls.checkString(1) ?? '';
      final cbRef = callbacks.ref(2);
      final future = context.storage.remove(key);
      if (cbRef != null) {
        unawaited(
          future.then((ok) {
            callbacks.invokeAndRelease(cbRef, [ok]);
          }).catchError((Object e) {
            callbacks.invokeAndRelease(cbRef, [false, e.toString()]);
          }),
        );
      } else {
        unawaited(future);
      }
      return 0;
    });
    ls.setField(-2, 'remove');

    ls.setGlobal('storage');
  }
}
