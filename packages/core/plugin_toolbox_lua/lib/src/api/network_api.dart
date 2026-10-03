import 'package:http/http.dart' as http;
import 'package:lua_dardo/lua.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';

class NetworkApi {
  static void bind(LuaState ls, PluginContext context) {
    ls.newTable();

    ls.pushDartFunction((ls) {
      if (!context.hasPermission(PluginPermission.network)) {
        ls.error2('权限不足: 插件未声明 network 权限');
        return 0;
      }
      final url = ls.checkString(1) ?? '';
      try {
        final res = http.get(Uri.parse(url));
        res.then((response) {
          // 异步转通知
        });
      } catch (e) {
        ls.error2('HTTP 请求失败: $e');
      }
      return 0;
    });
    ls.setField(-2, 'get');

    ls.setGlobal('network');
  }
}
