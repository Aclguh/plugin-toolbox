import 'package:lua_dardo/lua.dart';
import '../lua_engine.dart';

class DialogApi {
  static void bind(LuaState ls, LuaHostDelegate delegate) {
    ls.newTable();

    // dialog.toast(message)
    ls.pushDartFunction((ls) {
      final msg = ls.checkString(1) ?? '';
      delegate.showToast(msg);
      return 0;
    });
    ls.setField(-2, 'toast');

    // dialog.alert(title, message)
    ls.pushDartFunction((ls) {
      final title = ls.checkString(1) ?? '';
      final msg = ls.checkString(2) ?? '';
      delegate.showAlert(title, msg);
      return 0;
    });
    ls.setField(-2, 'alert');

    ls.setGlobal('dialog');
  }
}
