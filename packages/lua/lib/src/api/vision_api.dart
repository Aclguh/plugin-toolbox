import 'dart:async';
import 'package:lua_dardo/lua.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';
import '../lua_callback_invoker.dart';
import '../lua_engine.dart';

/// `vision` — 计算机视觉与图像识别 API。
///
/// 提供离线图片条形码/二维码解码等轻量视觉识别能力。
class VisionApi {
  static void bind(
    LuaState ls,
    PluginContext context,
    LuaHostDelegate delegate,
    LuaCallbackInvoker callbacks,
  ) {
    ls.newTable();

    // vision.decodeBarcode(relPath [, callback])
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
    ls.setField(-2, 'decodeBarcode');

    // vision.recognizeText(relPath, callback) -> { ok = bool, text = str, lines = [ str ] }
    ls.pushDartFunction((ls) {
      if (!context.hasPermission(PluginPermission.camera) &&
          !context.hasPermission(PluginPermission.photoLibrary) &&
          !context.hasPermission(PluginPermission.storage)) {
        ls.error2('权限不足: 插件未声明 camera/photoLibrary/storage 权限');
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
        delegate.recognizeText(fullPath).then((result) {
          if (cbRef != null) {
            if (result != null) {
              callbacks.invokeAndRelease(cbRef, [
                {'ok': true, ...result}
              ]);
            } else {
              callbacks.invokeAndRelease(cbRef, [
                {'ok': false, 'error': '未识别出文本或识别失败'}
              ]);
            }
          }
        }).catchError((Object err) {
          if (cbRef != null) {
            callbacks.invokeAndRelease(cbRef, [
              {'ok': false, 'error': err.toString()}
            ]);
          }
        }),
      );
      return 0;
    });
    ls.setField(-2, 'recognizeText');

    ls.setGlobal('vision');
  }
}
