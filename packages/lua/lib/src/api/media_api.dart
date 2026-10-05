import 'dart:async';
import 'package:lua_dardo/lua.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';
import '../lua_callback_invoker.dart';
import '../lua_engine.dart';

/// `media` — 多媒体与系统文件选择 API。
///
/// 允许用户在授权前提下选取相册图片或系统文件，由宿主安全放置于沙箱并返回相对路径。
class MediaApi {
  static void bind(
    LuaState ls,
    PluginContext context,
    LuaHostDelegate delegate,
    LuaCallbackInvoker callbacks,
    void Function(String key, dynamic value) writeState,
  ) {
    ls.newTable();

    // media.pickImage([callback])
    ls.pushDartFunction((ls) {
      if (!context.hasPermission(PluginPermission.photoLibrary)) {
        ls.error2('权限不足: 插件未声明 photoLibrary 权限');
        return 0;
      }

      final cbRef = callbacks.ref(1);
      unawaited(
        delegate.pickImage().then((relPath) {
          if (cbRef != null) {
            callbacks.invokeAndRelease(cbRef, [relPath]);
          } else if (relPath != null) {
            writeState('__picked_image', relPath);
          }
        }).catchError((Object e) {
          writeState('__media_error', e.toString());
          if (cbRef != null) {
            callbacks.invokeAndRelease(cbRef, [null]);
          }
        }),
      );
      return 0;
    });
    ls.setField(-2, 'pickImage');

    // media.pickFile([callback])
    ls.pushDartFunction((ls) {
      final cbRef = callbacks.ref(1);
      unawaited(
        delegate.pickFile().then((relPath) {
          if (cbRef != null) {
            callbacks.invokeAndRelease(cbRef, [relPath]);
          } else if (relPath != null) {
            writeState('__picked_file', relPath);
          }
        }).catchError((Object e) {
          writeState('__media_error', e.toString());
          if (cbRef != null) {
            callbacks.invokeAndRelease(cbRef, [null]);
          }
        }),
      );
      return 0;
    });
    ls.setField(-2, 'pickFile');

    ls.setGlobal('media');
  }
}
