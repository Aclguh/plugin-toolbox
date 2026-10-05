import 'package:lua_dardo/lua.dart';
import '../lua_engine.dart';

/// `ui` — 界面命令式交互控制 API。
///
/// 弥补声明式 UI 数据流在软键盘收起、主动轻提示等命令式场景的控制缺失。
class UiApi {
  static void bind(LuaState ls, LuaHostDelegate delegate) {
    ls.newTable();

    // ui.hideKeyboard()
    ls.pushDartFunction((ls) {
      delegate.hideKeyboard();
      return 0;
    });
    ls.setField(-2, 'hideKeyboard');

    // ui.toast(message)
    ls.pushDartFunction((ls) {
      final msg = ls.checkString(1) ?? '';
      delegate.showToast(msg);
      return 0;
    });
    ls.setField(-2, 'toast');

    ls.setGlobal('ui');
  }
}
