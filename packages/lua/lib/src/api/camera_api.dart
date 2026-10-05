import 'dart:async';
import 'package:lua_dardo/lua.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';
import '../lua_callback_invoker.dart';
import '../lua_engine.dart';

/// `camera` — 摄像头与扫码识别 API。
class CameraApi {
  static void bind(
    LuaState ls,
    PluginContext context,
    LuaHostDelegate delegate,
    LuaCallbackInvoker callbacks,
  ) {
    ls.newTable();

    // camera.scan([options, callback])
    // 调起摄像头扫码（条形码/二维码）
    ls.pushDartFunction((ls) {
      if (!context.hasPermission(PluginPermission.camera)) {
        ls.error2('权限不足: 插件未声明 camera 权限');
        return 0;
      }

      String? prompt;
      int? cbRef;

      if (ls.type(1) == LuaType.luaFunction) {
        cbRef = callbacks.ref(1);
      } else if (ls.type(1) == LuaType.luaString) {
        prompt = ls.toStr(1);
        cbRef = callbacks.ref(2);
      } else if (ls.type(1) == LuaType.luaTable) {
        ls.getField(1, 'prompt');
        if (ls.type(-1) == LuaType.luaString) prompt = ls.toStr(-1);
        ls.pop(1);
        cbRef = callbacks.ref(2);
      }

      unawaited(
        delegate.scanBarcode(prompt: prompt).then((result) {
          if (cbRef != null) {
            callbacks.invokeAndRelease(cbRef, [result]);
          } else {
            delegate.onStateChanged('__scanned_code', result);
          }
        }).catchError((Object err) {
          if (cbRef != null) {
            callbacks.invokeAndRelease(cbRef, [null]);
          } else {
            delegate.onStateChanged('__scanned_code', null);
          }
        }),
      );
      return 0;
    });
    ls.setField(-2, 'scan');

    // camera.decodeImage(relPath [, callback])
    // 对沙箱图片进行条形码/二维码解码
    ls.pushDartFunction((ls) {
      if (!context.hasPermission(PluginPermission.storage)) {
        ls.error2('权限不足: 插件未声明 storage 权限');
        return 0;
      }
      final relPath = ls.checkString(1) ?? '';
      final rootDir = context.rootDir;
      if (rootDir == null) {
        ls.error2('沙箱未挂载: 当前插件上下文缺少 rootDir');
        return 0;
      }
      if (!SandboxPath.isSafeSubpath(rootDir.path, relPath)) {
        ls.error2('非法路径: 禁止逃逸沙箱 ($relPath)');
        return 0;
      }
      final fullPath = '${rootDir.path}/$relPath';

      final cbRef = callbacks.ref(2);
      unawaited(
        delegate.decodeBarcodeFromImage(fullPath).then((result) {
          if (cbRef != null) {
            callbacks.invokeAndRelease(cbRef, [result]);
          } else {
            delegate.onStateChanged('__decoded_code', result);
          }
        }).catchError((Object err) {
          if (cbRef != null) {
            callbacks.invokeAndRelease(cbRef, [null]);
          } else {
            delegate.onStateChanged('__decoded_code', null);
          }
        }),
      );
      return 0;
    });
    ls.setField(-2, 'decodeImage');

    ls.setGlobal('camera');
  }
}
