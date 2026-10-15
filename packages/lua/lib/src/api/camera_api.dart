import 'dart:async';
import 'package:lua_dardo/lua.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';
import '../lua_callback_invoker.dart';
import '../lua_engine.dart';
import 'sandbox_utils.dart';

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
      final fullPath = resolveSandboxPath(ls, context, relPath);

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

    // camera.takePhoto([optionsTable | callback, callback])
    // 拍摄照片并保存至沙箱 (需 camera 与 storage 权限)
    ls.pushDartFunction((ls) {
      if (!context.hasPermission(PluginPermission.camera)) {
        ls.error2('权限不足: 插件未声明 camera 权限');
        return 0;
      }
      if (!context.hasPermission(PluginPermission.storage)) {
        ls.error2('权限不足: 插件未声明 storage 权限');
        return 0;
      }

      int quality = 90;
      String lensDirection = 'back';
      String? destRelPath;
      int? cbRef;

      if (ls.type(1) == LuaType.luaFunction) {
        cbRef = callbacks.ref(1);
      } else if (ls.type(1) == LuaType.luaTable) {
        ls.getField(1, 'quality');
        if (ls.isInteger(-1)) quality = ls.toInteger(-1).clamp(1, 100);
        ls.pop(1);

        ls.getField(1, 'lens');
        if (ls.isString(-1)) lensDirection = ls.toStr(-1) ?? 'back';
        ls.pop(1);

        ls.getField(1, 'destPath');
        if (ls.isString(-1)) destRelPath = ls.toStr(-1);
        ls.pop(1);

        if (ls.type(2) == LuaType.luaFunction) {
          cbRef = callbacks.ref(2);
        }
      }

      final effectiveRel = destRelPath ??
          'camera/photo_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final fullPath = resolveSandboxPath(ls, context, effectiveRel);

      unawaited(
        delegate
            .takePhoto(
          destPath: fullPath,
          quality: quality,
          lensDirection: lensDirection,
        )
            .then((savedFullPath) {
          final res = savedFullPath != null ? effectiveRel : null;
          if (cbRef != null) {
            callbacks.invokeAndRelease(cbRef, [res]);
          } else {
            delegate.onStateChanged('__captured_photo', res);
          }
        }).catchError((Object _) {
          if (cbRef != null) {
            callbacks.invokeAndRelease(cbRef, [null]);
          } else {
            delegate.onStateChanged('__captured_photo', null);
          }
        }),
      );
      return 0;
    });
    ls.setField(-2, 'takePhoto');

    ls.setGlobal('camera');
  }
}
