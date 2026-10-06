import 'dart:async';

import 'package:lua_dardo/lua.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';

import '../lua_callback_invoker.dart';
import '../lua_engine.dart';

/// `biometrics` — 设备生物认证 API (指纹 / 面容识别)。
///
/// 严格受限于 `biometrics` 权限，提供系统生物核验可用性查询与身份认证。
class BiometricsApi {
  static void bind(
    LuaState ls,
    PluginContext context,
    LuaHostDelegate delegate,
    LuaCallbackInvoker callbacks,
  ) {
    ls.newTable();

    void checkPermission(LuaState ls) {
      if (!context.hasPermission(PluginPermission.biometrics)) {
        ls.error2('权限不足: 插件未声明 biometrics 权限');
      }
    }

    // biometrics.isAvailable([callback]) -> bool
    ls.pushDartFunction((ls) {
      checkPermission(ls);
      final cbRef = callbacks.ref(1);

      unawaited(
        delegate.isBiometricsAvailable().then((available) {
          if (cbRef != null) {
            callbacks.invokeAndRelease(cbRef, [available]);
          } else {
            delegate.onStateChanged('__biometrics_available', available);
          }
        }).catchError((Object _) {
          if (cbRef != null) {
            callbacks.invokeAndRelease(cbRef, [false]);
          } else {
            delegate.onStateChanged('__biometrics_available', false);
          }
        }),
      );
      return 0;
    });
    ls.setField(-2, 'isAvailable');

    // biometrics.authenticate([reason | callback, callback])
    ls.pushDartFunction((ls) {
      checkPermission(ls);
      String? reason;
      int? cbRef;

      if (ls.type(1) == LuaType.luaFunction) {
        cbRef = callbacks.ref(1);
      } else if (ls.isString(1)) {
        reason = ls.toStr(1);
        if (ls.type(2) == LuaType.luaFunction) {
          cbRef = callbacks.ref(2);
        }
      }

      unawaited(
        delegate.authenticateBiometrics(reason: reason).then((result) {
          if (cbRef != null) {
            callbacks.invokeAndRelease(cbRef, [result]);
          } else {
            delegate.onStateChanged('__biometrics_success', result['success']);
            delegate.onStateChanged('__biometrics_error', result['error']);
          }
        }).catchError((Object e) {
          if (cbRef != null) {
            callbacks.invokeAndRelease(cbRef, [
              {'success': false, 'error': e.toString()}
            ]);
          }
        }),
      );
      return 0;
    });
    ls.setField(-2, 'authenticate');

    ls.setGlobal('biometrics');
  }
}
