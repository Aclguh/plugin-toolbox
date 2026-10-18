import 'dart:async';

import 'package:lua_dardo/lua.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';

import '../delegates/domain_delegates.dart';
import '../lua_callback_invoker.dart';
import 'api_guard.dart';

class ClipboardApi {
  /// [writeState] 即 LuaHostDelegate.onStateChanged：未提供回调时，
  /// 异步读取结果降级写入插件状态供脚本后续读取。
  static void bind(
    LuaState ls,
    PluginContext context,
    LuaClipboardDelegate clipboard,
    LuaCallbackInvoker callbacks,
    void Function(String key, dynamic value) writeState,
  ) {
    ls.newTable();

    // clipboard.set(text)
    ls.pushDartFunction((ls) {
      ApiGuard.checkPermission(ls, context, PluginPermission.clipboard);
      final text = ls.checkString(1) ?? '';
      clipboard.setClipboardText(text);
      return 0;
    });
    ls.setField(-2, 'set');

    // clipboard.get([callback])
    // 读取为异步操作，无法在同步 Lua 栈中直接返回值：
    // 传入回调函数则异步携带剪贴板文本（可能为 nil）回调，
    // 否则结果写入状态 __clipboard_value
    ls.pushDartFunction((ls) {
      ApiGuard.checkPermission(ls, context, PluginPermission.clipboard);
      // 与 storage.get 不同，clipboard.get 无必选首参：回调固定位于栈索引 1
      final cbRef = callbacks.ref(1);
      unawaited(
        clipboard.getClipboardText().then((text) {
          if (cbRef != null) {
            callbacks.invokeAndRelease(cbRef, [text]);
          } else if (text != null) {
            writeState('__clipboard_value', text);
          }
        }),
      );
      return 0;
    });
    ls.setField(-2, 'get');

    ls.setGlobal('clipboard');
  }
}
