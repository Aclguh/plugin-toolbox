import 'package:lua_dardo/lua.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';

import '../lua_callback_invoker.dart';
import '../lua_engine.dart';

/// `location` — 地理位置与海拔宿主 API。
class LocationApi {
  static void bind(
    LuaState ls,
    PluginContext context,
    LuaHostDelegate delegate,
    LuaCallbackInvoker callbacks,
  ) {
    ls.newTable();

    void checkPermission(LuaState ls) {
      if (!context.hasPermission(PluginPermission.location)) {
        ls.error2('权限不足: 插件未声明 location 权限');
      }
    }

    // location.isAvailable([callback]) -> bool
    ls.pushDartFunction((ls) {
      checkPermission(ls);
      if (ls.type(1) == LuaType.luaFunction) {
        final cbRef = callbacks.ref(1);
        if (cbRef != null) {
          delegate.isLocationAvailable().then((available) {
            callbacks.invokeAndRelease(cbRef, [available]);
          });
        }
        return 0;
      }
      ls.pushBoolean(false);
      return 1;
    });
    ls.setField(-2, 'isAvailable');

    // location.getCurrentPosition(callback) -> { ok = bool, latitude = num, longitude = num, altitude = num, accuracy = num, timestamp = num }
    ls.pushDartFunction((ls) {
      checkPermission(ls);
      final cbRef = callbacks.ref(1);
      if (cbRef != null) {
        delegate.getCurrentPosition().then((pos) {
          if (pos != null) {
            callbacks.invokeAndRelease(cbRef, [
              {'ok': true, ...pos}
            ]);
          } else {
            callbacks.invokeAndRelease(cbRef, [
              {'ok': false, 'error': '无法获取当前位置信息'}
            ]);
          }
        }).catchError((Object e) {
          callbacks.invokeAndRelease(cbRef, [
            {'ok': false, 'error': e.toString()}
          ]);
        });
      }
      return 0;
    });
    ls.setField(-2, 'getCurrentPosition');

    // location.getAltitude(callback) -> number
    ls.pushDartFunction((ls) {
      checkPermission(ls);
      final cbRef = callbacks.ref(1);
      if (cbRef != null) {
        delegate.getCurrentPosition().then((pos) {
          final altitude = (pos != null ? pos['altitude'] : 0.0) ?? 0.0;
          callbacks.invokeAndRelease(cbRef, [altitude]);
        }).catchError((Object _) {
          callbacks.invokeAndRelease(cbRef, [0.0]);
        });
      }
      return 0;
    });
    ls.setField(-2, 'getAltitude');

    ls.setGlobal('location');
  }
}
