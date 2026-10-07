import 'package:lua_dardo/lua.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';

import '../lua_callback_invoker.dart';
import '../lua_engine.dart';

/// `screen` — 屏幕常亮与亮度控制宿主 API。
class ScreenApi {
  static void bind(
    LuaState ls,
    PluginContext context,
    LuaHostDelegate delegate,
    LuaCallbackInvoker callbacks,
  ) {
    ls.newTable();

    void checkPermission(LuaState ls) {
      if (!context.hasPermission(PluginPermission.screen)) {
        ls.error2('权限不足: 插件未声明 screen 权限');
      }
    }

    // screen.setKeepScreenOn(enabled [, callback])
    ls.pushDartFunction((ls) {
      checkPermission(ls);
      final enabled = ls.toBoolean(1);
      int? cbRef;
      if (ls.type(2) == LuaType.luaFunction) {
        cbRef = callbacks.ref(2);
      }

      delegate.setKeepScreenOn(enabled).then((success) {
        if (cbRef != null) {
          callbacks.invokeAndRelease(cbRef, [success]);
        }
      });
      return 0;
    });
    ls.setField(-2, 'setKeepScreenOn');

    // screen.setBrightness(brightness [, callback])  brightness: 0.0 ~ 1.0
    ls.pushDartFunction((ls) {
      checkPermission(ls);
      final brightness = ls.toNumber(1).clamp(0.0, 1.0);
      int? cbRef;
      if (ls.type(2) == LuaType.luaFunction) {
        cbRef = callbacks.ref(2);
      }

      delegate.setBrightness(brightness).then((success) {
        if (cbRef != null) {
          callbacks.invokeAndRelease(cbRef, [success]);
        }
      });
      return 0;
    });
    ls.setField(-2, 'setBrightness');

    // screen.getBrightness([callback]) -> number (0.0 ~ 1.0)
    ls.pushDartFunction((ls) {
      checkPermission(ls);
      if (ls.type(1) == LuaType.luaFunction) {
        final cbRef = callbacks.ref(1);
        if (cbRef != null) {
          delegate.getBrightness().then((val) {
            callbacks.invokeAndRelease(cbRef, [val]);
          });
        }
        return 0;
      }

      // 同步调用返回默认
      ls.pushNumber(1.0);
      return 1;
    });
    ls.setField(-2, 'getBrightness');

    // screen.resetBrightness([callback])
    ls.pushDartFunction((ls) {
      checkPermission(ls);
      int? cbRef;
      if (ls.type(1) == LuaType.luaFunction) {
        cbRef = callbacks.ref(1);
      }

      delegate.resetBrightness().then((success) {
        if (cbRef != null) {
          callbacks.invokeAndRelease(cbRef, [success]);
        }
      });
      return 0;
    });
    ls.setField(-2, 'resetBrightness');

    ls.setGlobal('screen');
  }
}
