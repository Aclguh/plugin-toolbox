import 'dart:async';
import 'dart:io';

import 'package:lua_dardo/lua.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';

import '../../delegates/domain_delegates.dart';
import '../../lua_callback_invoker.dart';
import '../sandbox_utils.dart';

/// 沙箱文件系统外部系统交互处理器 (保存相册、导出文件、选取外部文件)
class FsExternalHandler {
  static void register(
    LuaState ls,
    PluginContext context,
    LuaHostDelegate delegate,
    LuaCallbackInvoker callbacks,
  ) {
    void checkStoragePermission(LuaState ls) {
      if (!context.hasPermission(PluginPermission.storage)) {
        ls.error2('权限不足: 插件未声明 storage 权限');
      }
    }

    String resolveSafePath(LuaState ls, String relPath) =>
        resolveSandboxPath(ls, context, relPath);

    // fs.saveToGallery(relPath [, callback])
    ls.pushDartFunction((ls) {
      checkStoragePermission(ls);
      final relPath = ls.checkString(1) ?? '';
      final fullPath = resolveSafePath(ls, relPath);
      final file = File(fullPath);
      if (!file.existsSync()) {
        ls.error2('文件不存在: $relPath');
        return 0;
      }

      final lower = relPath.toLowerCase();
      final isImage = lower.endsWith('.png') ||
          lower.endsWith('.jpg') ||
          lower.endsWith('.jpeg') ||
          lower.endsWith('.webp') ||
          lower.endsWith('.gif') ||
          lower.endsWith('.bmp');
      if (!isImage) {
        ls.error2('类型不支持: 仅支持将图片文件保存至系统相册 ($relPath)');
        return 0;
      }

      final cbRef = callbacks.ref(2);
      unawaited(
        delegate.saveToGallery(fullPath).then((success) {
          if (cbRef != null) {
            callbacks.invokeAndRelease(cbRef, [success]);
          } else {
            delegate.onStateChanged('__fs_save_gallery', success);
          }
        }).catchError((Object err) {
          if (cbRef != null) {
            callbacks.invokeAndRelease(cbRef, [false, err.toString()]);
          } else {
            delegate.onStateChanged('__fs_save_gallery', false);
          }
        }),
      );
      return 0;
    });
    ls.setField(-2, 'saveToGallery');

    // fs.exportFile(relPath [, defaultName, callback])
    ls.pushDartFunction((ls) {
      checkStoragePermission(ls);
      final relPath = ls.checkString(1) ?? '';
      final fullPath = resolveSafePath(ls, relPath);
      final file = File(fullPath);
      if (!file.existsSync()) {
        ls.error2('文件不存在: $relPath');
        return 0;
      }

      String? defaultName;
      int? cbRef;

      if (ls.type(2) == LuaType.luaFunction) {
        cbRef = callbacks.ref(2);
      } else {
        if (!ls.isNoneOrNil(2)) defaultName = ls.toStr(2);
        if (ls.type(3) == LuaType.luaFunction) {
          cbRef = callbacks.ref(3);
        }
      }

      unawaited(
        delegate.exportFile(fullPath, defaultName: defaultName).then((success) {
          if (cbRef != null) {
            callbacks.invokeAndRelease(cbRef, [success]);
          } else {
            delegate.onStateChanged('__fs_export_file', success);
          }
        }).catchError((Object err) {
          if (cbRef != null) {
            callbacks.invokeAndRelease(cbRef, [false, err.toString()]);
          } else {
            delegate.onStateChanged('__fs_export_file', false);
          }
        }),
      );
      return 0;
    });
    ls.setField(-2, 'exportFile');

    // fs.pickFile([options, callback])
    // 选取外部文件并安全复制至插件沙箱 data/ 目录
    ls.pushDartFunction((ls) {
      checkStoragePermission(ls);
      List<String>? allowedExtensions;
      int? cbRef;

      if (ls.type(1) == LuaType.luaFunction) {
        cbRef = callbacks.ref(1);
      } else if (ls.type(1) == LuaType.luaTable) {
        ls.getField(1, 'allowedExtensions');
        if (ls.type(-1) == LuaType.luaTable) {
          final len = ls.rawLen(-1);
          final exts = <String>[];
          for (int i = 1; i <= len; i++) {
            ls.rawGetI(-1, i);
            if (ls.type(-1) == LuaType.luaString) {
              exts.add(ls.toStr(-1)!);
            }
            ls.pop(1);
          }
          if (exts.isNotEmpty) allowedExtensions = exts;
        }
        ls.pop(1);
        if (ls.type(2) == LuaType.luaFunction) {
          cbRef = callbacks.ref(2);
        }
      } else if (ls.type(1) == LuaType.luaString) {
        allowedExtensions = [ls.toStr(1)!];
        if (ls.type(2) == LuaType.luaFunction) {
          cbRef = callbacks.ref(2);
        }
      }

      unawaited(
        delegate.pickFile(allowedExtensions: allowedExtensions).then((relPath) {
          if (cbRef != null) {
            callbacks.invokeAndRelease(cbRef, [relPath]);
          } else if (relPath != null) {
            delegate.onStateChanged('__picked_file', relPath);
          }
        }).catchError((Object e) {
          if (cbRef != null) {
            callbacks.invokeAndRelease(cbRef, [null]);
          }
        }),
      );
      return 0;
    });
    ls.setField(-2, 'pickFile');
  }
}
