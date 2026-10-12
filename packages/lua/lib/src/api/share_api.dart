import 'dart:async';
import 'dart:io';
import 'package:lua_dardo/lua.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';
import '../lua_callback_invoker.dart';
import '../lua_engine.dart';
import 'sandbox_utils.dart';

/// `share` — 系统分享 API。
///
/// 调起系统底层分享面板，将插件生成或处理后的文本与沙箱文件分享至外部应用。
class ShareApi {
  static void bind(
    LuaState ls,
    LuaHostDelegate delegate,
    PluginContext context, [
    LuaCallbackInvoker? callbacks,
  ]) {
    ls.newTable();

    // share.text(content [, subject])
    ls.pushDartFunction((ls) {
      final text = ls.checkString(1) ?? '';
      final subject = ls.isNoneOrNil(2) ? null : ls.toStr(2);
      unawaited(delegate.shareText(text, subject: subject));
      return 0;
    });
    ls.setField(-2, 'text');

    // share.file(relPath [, mimeType, subject, callback])
    // 严格受限于插件独立沙箱目录，经 [SandboxPath.isSafeSubpath] 校验防路径穿越。
    ls.pushDartFunction((ls) {
      final relPath = ls.checkString(1) ?? '';
      final fullPath = resolveSandboxPath(ls, context, relPath);
      final file = File(fullPath);
      if (!file.existsSync()) {
        ls.error2('文件不存在: $relPath');
        return 0;
      }

      String? mimeType;
      String? subject;
      int? cbRef;

      if (ls.type(2) == LuaType.luaFunction) {
        cbRef = callbacks?.ref(2);
      } else {
        if (!ls.isNoneOrNil(2)) mimeType = ls.toStr(2);
        if (ls.type(3) == LuaType.luaFunction) {
          cbRef = callbacks?.ref(3);
        } else {
          if (!ls.isNoneOrNil(3)) subject = ls.toStr(3);
          if (ls.type(4) == LuaType.luaFunction) {
            cbRef = callbacks?.ref(4);
          }
        }
      }

      unawaited(
        delegate
            .shareFile(fullPath, mimeType: mimeType, subject: subject)
            .then((success) {
          if (cbRef != null) {
            callbacks?.invokeAndRelease(cbRef, [success]);
          } else {
            delegate.onStateChanged('__share_file_result', success);
          }
        }).catchError((Object err) {
          if (cbRef != null) {
            callbacks?.invokeAndRelease(cbRef, [false, err.toString()]);
          } else {
            delegate.onStateChanged('__share_file_result', false);
          }
        }),
      );
      return 0;
    });
    ls.setField(-2, 'file');

    ls.setGlobal('share');
  }
}
