import 'dart:async';
import 'package:lua_dardo/lua.dart';
import '../lua_engine.dart';

/// `share` — 系统分享 API。
///
/// 调起系统底层分享面板，将插件生成或处理后的内容分享至外部应用。
class ShareApi {
  static void bind(LuaState ls, LuaHostDelegate delegate) {
    ls.newTable();

    // share.text(content [, subject])
    ls.pushDartFunction((ls) {
      final text = ls.checkString(1) ?? '';
      final subject = ls.isNoneOrNil(2) ? null : ls.toStr(2);
      unawaited(delegate.shareText(text, subject: subject));
      return 0;
    });
    ls.setField(-2, 'text');

    ls.setGlobal('share');
  }
}
