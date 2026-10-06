import 'dart:async';
import 'package:lua_dardo/lua.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';
import '../lua_callback_invoker.dart';
import '../lua_engine.dart';

/// `notification` — 本地系统通知与定时提醒 API。
class NotificationApi {
  static void bind(
    LuaState ls,
    PluginContext context,
    LuaHostDelegate delegate,
    LuaCallbackInvoker callbacks,
  ) {
    ls.newTable();

    void checkNotificationPermission(LuaState ls) {
      if (!context.hasPermission(PluginPermission.notification)) {
        ls.error2('权限不足: 插件未声明 notification 权限');
      }
    }

    // notification.show(title, body [, payload, callback])
    ls.pushDartFunction((ls) {
      checkNotificationPermission(ls);
      final title = ls.checkString(1) ?? '';
      final body = ls.checkString(2) ?? '';
      String? payload;
      int? cbRef;

      if (ls.type(3) == LuaType.luaFunction) {
        cbRef = callbacks.ref(3);
      } else if (ls.type(3) == LuaType.luaString) {
        payload = ls.toStr(3);
        cbRef = callbacks.ref(4);
      }

      unawaited(
        delegate
            .showNotification(title: title, body: body, payload: payload)
            .then((id) {
          if (cbRef != null) {
            callbacks.invokeAndRelease(cbRef, [id]);
          } else {
            delegate.onStateChanged('__last_notification_id', id);
          }
        }).catchError((Object _) {
          if (cbRef != null) {
            callbacks.invokeAndRelease(cbRef, [-1]);
          }
        }),
      );
      return 0;
    });
    ls.setField(-2, 'show');

    // notification.schedule(title, body, delaySeconds [, payload, callback])
    ls.pushDartFunction((ls) {
      checkNotificationPermission(ls);
      final title = ls.checkString(1) ?? '';
      final body = ls.checkString(2) ?? '';
      final delaySeconds = ls.checkInteger(3) ?? 0;
      String? payload;
      int? cbRef;

      if (ls.type(4) == LuaType.luaFunction) {
        cbRef = callbacks.ref(4);
      } else if (ls.type(4) == LuaType.luaString) {
        payload = ls.toStr(4);
        cbRef = callbacks.ref(5);
      }

      unawaited(
        delegate
            .scheduleNotification(
          title: title,
          body: body,
          delaySeconds: delaySeconds,
          payload: payload,
        )
            .then((id) {
          if (cbRef != null) {
            callbacks.invokeAndRelease(cbRef, [id]);
          } else {
            delegate.onStateChanged('__last_notification_id', id);
          }
        }).catchError((Object _) {
          if (cbRef != null) {
            callbacks.invokeAndRelease(cbRef, [-1]);
          }
        }),
      );
      return 0;
    });
    ls.setField(-2, 'schedule');

    // notification.cancel(id [, callback])
    ls.pushDartFunction((ls) {
      checkNotificationPermission(ls);
      final id = ls.checkInteger(1) ?? -1;
      final cbRef = callbacks.ref(2);

      unawaited(
        delegate.cancelNotification(id).then((ok) {
          if (cbRef != null) {
            callbacks.invokeAndRelease(cbRef, [ok]);
          }
        }).catchError((Object _) {
          if (cbRef != null) {
            callbacks.invokeAndRelease(cbRef, [false]);
          }
        }),
      );
      return 0;
    });
    ls.setField(-2, 'cancel');

    // notification.cancelAll([callback])
    ls.pushDartFunction((ls) {
      checkNotificationPermission(ls);
      final cbRef = callbacks.ref(1);

      unawaited(
        delegate.cancelAllNotifications().then((ok) {
          if (cbRef != null) {
            callbacks.invokeAndRelease(cbRef, [ok]);
          }
        }).catchError((Object _) {
          if (cbRef != null) {
            callbacks.invokeAndRelease(cbRef, [false]);
          }
        }),
      );
      return 0;
    });
    ls.setField(-2, 'cancelAll');

    ls.setGlobal('notification');
  }
}
