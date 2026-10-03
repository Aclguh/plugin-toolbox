import 'package:flutter/services.dart';
import 'package:lua_dardo/lua.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';

class ClipboardApi {
  static void bind(LuaState ls, PluginContext context) {
    ls.newTable();

    // clipboard.set(text)
    ls.pushDartFunction((ls) {
      if (!context.hasPermission(PluginPermission.clipboard)) {
        ls.error2('权限不足: 插件未声明 clipboard 权限');
        return 0;
      }
      final text = ls.checkString(1) ?? '';
      Clipboard.setData(ClipboardData(text: text));
      return 0;
    });
    ls.setField(-2, 'set');

    ls.setGlobal('clipboard');
  }
}
