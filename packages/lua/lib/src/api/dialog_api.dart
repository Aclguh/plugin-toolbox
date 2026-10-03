import 'dart:async';

import 'package:lua_dardo/lua.dart';
import '../lua_callback_invoker.dart';
import '../lua_engine.dart';

class DialogApi {
  static void bind(
    LuaState ls,
    LuaHostDelegate delegate,
    LuaCallbackInvoker callbacks,
  ) {
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

    // dialog.confirm(title, message [, callback])
    // 用户选择为异步结果：传入回调函数则携带布尔结果回调，
    // 否则写入状态 __dialog_confirm
    ls.pushDartFunction((ls) {
      final title = ls.checkString(1) ?? '';
      final msg = ls.checkString(2) ?? '';
      final cbRef = callbacks.ref(3);
      unawaited(
        delegate.showConfirm(title, msg).then((confirmed) {
          if (cbRef != null) {
            callbacks.invokeAndRelease(cbRef, [confirmed]);
          } else {
            delegate.onStateChanged('__dialog_confirm', confirmed);
          }
        }),
      );
      return 0;
    });
    ls.setField(-2, 'confirm');

    ls.setGlobal('dialog');
  }
}
