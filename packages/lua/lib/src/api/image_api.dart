import 'dart:async';
import 'package:lua_dardo/lua.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';
import '../lua_callback_invoker.dart';
import '../lua_engine.dart';

/// `image` — 图像处理与元数据 API (压缩 / 裁剪 / 格式转换 / EXIF 擦除)。
class ImageApi {
  static void bind(
    LuaState ls,
    PluginContext context,
    LuaHostDelegate delegate,
    LuaCallbackInvoker callbacks,
  ) {
    ls.newTable();

    void checkStorage(LuaState ls) {
      if (!context.hasPermission(PluginPermission.storage)) {
        ls.error2('权限不足: 插件未声明 storage 权限');
      }
    }

    String resolveSafeFullPath(LuaState ls, String relPath) {
      final rootDir = context.rootDir;
      if (rootDir == null) {
        ls.error2('沙箱未挂载: 当前插件上下文缺少 rootDir');
        return '';
      }
      if (!SandboxPath.isSafeSubpath(rootDir.path, relPath)) {
        ls.error2('非法路径: 禁止逃逸沙箱 ($relPath)');
        return '';
      }
      return '${rootDir.path}/$relPath';
    }

    String defaultTarget(String srcRel, String suffix, String ext) {
      final lastSlash = srcRel.lastIndexOf('/');
      final dir = lastSlash >= 0 ? srcRel.substring(0, lastSlash + 1) : '';
      final fileName = lastSlash >= 0 ? srcRel.substring(lastSlash + 1) : srcRel;
      final dot = fileName.lastIndexOf('.');
      final name = dot >= 0 ? fileName.substring(0, dot) : fileName;
      return '$dir${name}_$suffix.$ext';
    }

    // image.info(relPath [, callback])
    // -> table {width, height, format, size}
    ls.pushDartFunction((ls) {
      checkStorage(ls);
      final relPath = ls.checkString(1) ?? '';
      final fullPath = resolveSafeFullPath(ls, relPath);
      final cbRef = callbacks.ref(2);

      unawaited(
        delegate.imageInfo(fullPath).then((info) {
          if (cbRef != null) {
            callbacks.invokeAndRelease(cbRef, [info]);
          } else {
            delegate.onStateChanged('__image_info', info);
          }
        }).catchError((Object _) {
          if (cbRef != null) {
            callbacks.invokeAndRelease(cbRef, [null]);
          } else {
            delegate.onStateChanged('__image_info', null);
          }
        }),
      );
      return 0;
    });
    ls.setField(-2, 'info');

    // image.compress(relPath, quality [, targetPath, callback])
    ls.pushDartFunction((ls) {
      checkStorage(ls);
      final relPath = ls.checkString(1) ?? '';
      final fullSrc = resolveSafeFullPath(ls, relPath);
      final quality = (ls.checkInteger(2) ?? 80).clamp(1, 100);

      String? targetRel;
      int? cbRef;

      if (ls.type(3) == LuaType.luaFunction) {
        cbRef = callbacks.ref(3);
      } else if (ls.type(3) == LuaType.luaString) {
        targetRel = ls.toStr(3);
        cbRef = callbacks.ref(4);
      }

      final effectiveTargetRel = targetRel ?? defaultTarget(relPath, 'compressed', 'jpg');
      final fullDest = resolveSafeFullPath(ls, effectiveTargetRel);

      unawaited(
        delegate.compressImage(fullSrc, fullDest, quality: quality).then((ok) {
          final res = ok ? effectiveTargetRel : null;
          if (cbRef != null) {
            callbacks.invokeAndRelease(cbRef, [res]);
          } else {
            delegate.onStateChanged('__compressed_image', res);
          }
        }).catchError((Object _) {
          if (cbRef != null) {
            callbacks.invokeAndRelease(cbRef, [null]);
          } else {
            delegate.onStateChanged('__compressed_image', null);
          }
        }),
      );
      return 0;
    });
    ls.setField(-2, 'compress');

    // image.crop(relPath, x, y, width, height [, targetPath, callback])
    ls.pushDartFunction((ls) {
      checkStorage(ls);
      final relPath = ls.checkString(1) ?? '';
      final fullSrc = resolveSafeFullPath(ls, relPath);
      final x = ls.checkInteger(2) ?? 0;
      final y = ls.checkInteger(3) ?? 0;
      final w = ls.checkInteger(4) ?? 0;
      final h = ls.checkInteger(5) ?? 0;

      String? targetRel;
      int? cbRef;

      if (ls.type(6) == LuaType.luaFunction) {
        cbRef = callbacks.ref(6);
      } else if (ls.type(6) == LuaType.luaString) {
        targetRel = ls.toStr(6);
        cbRef = callbacks.ref(7);
      }

      final effectiveTargetRel = targetRel ?? defaultTarget(relPath, 'cropped', 'png');
      final fullDest = resolveSafeFullPath(ls, effectiveTargetRel);

      unawaited(
        delegate.cropImage(fullSrc, fullDest, x: x, y: y, width: w, height: h).then((ok) {
          final res = ok ? effectiveTargetRel : null;
          if (cbRef != null) {
            callbacks.invokeAndRelease(cbRef, [res]);
          } else {
            delegate.onStateChanged('__cropped_image', res);
          }
        }).catchError((Object _) {
          if (cbRef != null) {
            callbacks.invokeAndRelease(cbRef, [null]);
          } else {
            delegate.onStateChanged('__cropped_image', null);
          }
        }),
      );
      return 0;
    });
    ls.setField(-2, 'crop');

    // image.convert(relPath, format [, targetPath, callback])
    ls.pushDartFunction((ls) {
      checkStorage(ls);
      final relPath = ls.checkString(1) ?? '';
      final fullSrc = resolveSafeFullPath(ls, relPath);
      final format = (ls.checkString(2) ?? 'png').toLowerCase();

      String? targetRel;
      int? cbRef;

      if (ls.type(3) == LuaType.luaFunction) {
        cbRef = callbacks.ref(3);
      } else if (ls.type(3) == LuaType.luaString) {
        targetRel = ls.toStr(3);
        cbRef = callbacks.ref(4);
      }

      final ext = format == 'jpeg' ? 'jpg' : format;
      final effectiveTargetRel = targetRel ?? defaultTarget(relPath, 'converted', ext);
      final fullDest = resolveSafeFullPath(ls, effectiveTargetRel);

      unawaited(
        delegate.convertImage(fullSrc, fullDest, format: format).then((ok) {
          final res = ok ? effectiveTargetRel : null;
          if (cbRef != null) {
            callbacks.invokeAndRelease(cbRef, [res]);
          } else {
            delegate.onStateChanged('__converted_image', res);
          }
        }).catchError((Object _) {
          if (cbRef != null) {
            callbacks.invokeAndRelease(cbRef, [null]);
          } else {
            delegate.onStateChanged('__converted_image', null);
          }
        }),
      );
      return 0;
    });
    ls.setField(-2, 'convert');

    // image.stripExif(relPath [, targetPath, callback])
    ls.pushDartFunction((ls) {
      checkStorage(ls);
      final relPath = ls.checkString(1) ?? '';
      final fullSrc = resolveSafeFullPath(ls, relPath);

      String? targetRel;
      int? cbRef;

      if (ls.type(2) == LuaType.luaFunction) {
        cbRef = callbacks.ref(2);
      } else if (ls.type(2) == LuaType.luaString) {
        targetRel = ls.toStr(2);
        cbRef = callbacks.ref(3);
      }

      final effectiveTargetRel = targetRel ?? defaultTarget(relPath, 'clean', 'jpg');
      final fullDest = resolveSafeFullPath(ls, effectiveTargetRel);

      unawaited(
        delegate.stripExifImage(fullSrc, fullDest).then((ok) {
          final res = ok ? effectiveTargetRel : null;
          if (cbRef != null) {
            callbacks.invokeAndRelease(cbRef, [res]);
          } else {
            delegate.onStateChanged('__clean_image', res);
          }
        }).catchError((Object _) {
          if (cbRef != null) {
            callbacks.invokeAndRelease(cbRef, [null]);
          } else {
            delegate.onStateChanged('__clean_image', null);
          }
        }),
      );
      return 0;
    });
    ls.setField(-2, 'stripExif');

    ls.setGlobal('image');
  }
}
