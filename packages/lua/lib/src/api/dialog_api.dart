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

    // dialog.pickDate([options, callback])
    // options 可以为 string（initialDate）或 table { initialDate, firstDate, lastDate }
    // callback(dateStr) -> dateStr 为 'YYYY-MM-DD' 或 nil（用户取消）
    // 若未传 callback，则写入状态 '__dialog_date'
    ls.pushDartFunction((ls) {
      String? initialDate;
      String? firstDate;
      String? lastDate;
      int? cbRef;

      if (ls.type(1) == LuaType.luaFunction) {
        cbRef = callbacks.ref(1);
      } else if (ls.type(1) == LuaType.luaString) {
        initialDate = ls.toStr(1);
        cbRef = callbacks.ref(2);
      } else if (ls.type(1) == LuaType.luaTable) {
        ls.getField(1, 'initialDate');
        if (ls.type(-1) == LuaType.luaString) initialDate = ls.toStr(-1);
        ls.pop(1);

        ls.getField(1, 'firstDate');
        if (ls.type(-1) == LuaType.luaString) firstDate = ls.toStr(-1);
        ls.pop(1);

        ls.getField(1, 'lastDate');
        if (ls.type(-1) == LuaType.luaString) lastDate = ls.toStr(-1);
        ls.pop(1);

        cbRef = callbacks.ref(2);
      }

      unawaited(
        delegate
            .pickDate(
              initialDate: initialDate,
              firstDate: firstDate,
              lastDate: lastDate,
            )
            .then((selectedDate) {
              if (cbRef != null) {
                callbacks.invokeAndRelease(cbRef, [selectedDate]);
              } else {
                delegate.onStateChanged('__dialog_date', selectedDate);
              }
            }),
      );
      return 0;
    });
    ls.setField(-2, 'pickDate');

    // dialog.pickTime([options, callback])
    // options 可以为 string（initialTime）或 table { initialTime }
    // callback(timeStr) -> timeStr 为 'HH:mm' 或 nil（用户取消）
    // 若未传 callback，则写入状态 '__dialog_time'
    ls.pushDartFunction((ls) {
      String? initialTime;
      int? cbRef;

      if (ls.type(1) == LuaType.luaFunction) {
        cbRef = callbacks.ref(1);
      } else if (ls.type(1) == LuaType.luaString) {
        initialTime = ls.toStr(1);
        cbRef = callbacks.ref(2);
      } else if (ls.type(1) == LuaType.luaTable) {
        ls.getField(1, 'initialTime');
        if (ls.type(-1) == LuaType.luaString) initialTime = ls.toStr(-1);
        ls.pop(1);

        cbRef = callbacks.ref(2);
      }

      unawaited(
        delegate.pickTime(initialTime: initialTime).then((selectedTime) {
          if (cbRef != null) {
            callbacks.invokeAndRelease(cbRef, [selectedTime]);
          } else {
            delegate.onStateChanged('__dialog_time', selectedTime);
          }
        }),
      );
      return 0;
    });
    ls.setField(-2, 'pickTime');

    ls.setGlobal('dialog');
  }
}
