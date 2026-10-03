import 'dart:async';
import 'package:lua_dardo/lua.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';

class StorageApi {
  static void bind(LuaState ls, PluginContext context) {
    ls.newTable();

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

    ls.setGlobal('storage');
  }
}
