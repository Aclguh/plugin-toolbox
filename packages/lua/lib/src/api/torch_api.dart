import 'dart:async';

import 'package:lua_dardo/lua.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';

import '../lua_callback_invoker.dart';
import '../lua_engine.dart';

/// `torch` — 设备手电筒 / 闪光灯控制 API。
///
/// 需声明 `torch` 权限，提供手电筒开关控制与状态读取。
class TorchApi {
  static void bind(
    LuaState ls,
    PluginContext context,
    LuaHostDelegate delegate,
    LuaCallbackInvoker callbacks,
  ) {
    ls.newTable();

    void checkPermission(LuaState ls) {
      if (!context.hasPermission(PluginPermission.torch)) {
        ls.error2('权限不足: 插件未声明 torch 权限');
      }
    }

    // torch.on([callback])
    ls.pushDartFunction((ls) {
      checkPermission(ls);
      final cbRef = callbacks.ref(1);
      unawaited(
        delegate.setTorch(true).then((success) {
          if (cbRef != null) {
            callbacks.invokeAndRelease(cbRef, [success]);
          }
        }),
      );
      return 0;
    });
    ls.setField(-2, 'on');

    // torch.off([callback])
    ls.pushDartFunction((ls) {
      checkPermission(ls);
      final cbRef = callbacks.ref(1);
      unawaited(
        delegate.setTorch(false).then((success) {
          if (cbRef != null) {
            callbacks.invokeAndRelease(cbRef, [success]);
          }
        }),
      );
      return 0;
    });
    ls.setField(-2, 'off');

    // torch.toggle([callback])
    ls.pushDartFunction((ls) {
      checkPermission(ls);
      final cbRef = callbacks.ref(1);
      final nextState = !delegate.isTorchOn;
      unawaited(
        delegate.setTorch(nextState).then((success) {
          if (cbRef != null) {
            callbacks.invokeAndRelease(cbRef, [success, nextState]);
          }
        }),
      );
      return 0;
    });
    ls.setField(-2, 'toggle');

    // torch.isOn() -> bool
    ls.pushDartFunction((ls) {
      checkPermission(ls);
      ls.pushBoolean(delegate.isTorchOn);
      return 1;
    });
    ls.setField(-2, 'isOn');

    ls.setGlobal('torch');
  }
}
