import 'dart:async';
import 'dart:io';

import 'package:lua_dardo/lua.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';

import '../lua_callback_invoker.dart';

/// `websocket` — 原生 WebSocket 双向全双工网络连接 API。
///
/// 严格受限于 `network` 权限，支持 ws/wss 握手、文本/二进制数据帧收发、
/// 错误捕获与关闭回调，活跃连接在引擎关闭时由宿主自动注销回收。
class WebSocketApi {
  final Map<String, WebSocket> _sockets = {};
  final Map<String, StreamSubscription> _subscriptions = {};
  final Set<String> _pendingWs = {};
  final Set<int> _callbackRefs = {};
  int _nextId = 1;

  void bind(
    LuaState ls,
    PluginContext context,
    LuaCallbackInvoker callbacks,
  ) {
    ls.newTable();

    void checkPermission(LuaState ls) {
      if (!context.hasPermission(PluginPermission.network)) {
        ls.error2('权限不足: 插件未声明 network 权限');
      }
    }

    // websocket.connect(url, optionsTable) -> string (wsId)
    ls.pushDartFunction((ls) {
      checkPermission(ls);
      final url = ls.checkString(1) ?? '';

      int? onOpenRef;
      int? onMessageRef;
      int? onErrorRef;
      int? onCloseRef;
      Map<String, dynamic>? customHeaders;

      if (ls.type(2) == LuaType.luaTable) {
        ls.getField(2, 'onOpen');
        if (ls.type(-1) == LuaType.luaFunction) {
          onOpenRef = callbacks.ref(-1);
          if (onOpenRef != null) _callbackRefs.add(onOpenRef);
        }
        ls.pop(1);

        ls.getField(2, 'onMessage');
        if (ls.type(-1) == LuaType.luaFunction) {
          onMessageRef = callbacks.ref(-1);
          if (onMessageRef != null) _callbackRefs.add(onMessageRef);
        }
        ls.pop(1);

        ls.getField(2, 'onError');
        if (ls.type(-1) == LuaType.luaFunction) {
          onErrorRef = callbacks.ref(-1);
          if (onErrorRef != null) _callbackRefs.add(onErrorRef);
        }
        ls.pop(1);

        ls.getField(2, 'onClose');
        if (ls.type(-1) == LuaType.luaFunction) {
          onCloseRef = callbacks.ref(-1);
          if (onCloseRef != null) _callbackRefs.add(onCloseRef);
        }
        ls.pop(1);

        ls.getField(2, 'headers');
        if (ls.type(-1) == LuaType.luaTable) {
          customHeaders = <String, dynamic>{};
          ls.pushNil();
          while (ls.next(-2)) {
            final k = ls.toStr(-2);
            final v = ls.toStr(-1);
            if (k != null && v != null) {
              customHeaders[k] = v;
            }
            ls.pop(1);
          }
        }
        ls.pop(1);
      }

      final Uri uri;
      try {
        uri = Uri.parse(url);
      } on FormatException catch (e) {
        ls.error2('URL 不合法: $e');
        return 0;
      }

      if (!context.isHostAllowed(uri.host)) {
        if (onErrorRef != null) {
          callbacks.invoke(onErrorRef, ['', '域名不在白名单内: ${uri.host}']);
        }
        ls.pushString('');
        return 1;
      }

      final wsId = 'ws_${_nextId++}';
      _pendingWs.add(wsId);

      unawaited(
        WebSocket.connect(url, headers: customHeaders).then((ws) {
          if (!_pendingWs.remove(wsId)) {
            ws.close();
            return;
          }
          _sockets[wsId] = ws;

          if (onOpenRef != null) {
            callbacks.invoke(onOpenRef, [wsId]);
          }

          final sub = ws.listen(
            (data) {
              if (onMessageRef != null) {
                callbacks.invoke(onMessageRef, [wsId, data.toString()]);
              }
            },
            onError: (Object error) {
              if (onErrorRef != null) {
                callbacks.invoke(onErrorRef, [wsId, error.toString()]);
              }
            },
            onDone: () {
              final code = ws.closeCode ?? 1000;
              final reason = ws.closeReason ?? '';
              _closeWs(wsId);
              if (onCloseRef != null) {
                callbacks.invoke(onCloseRef, [wsId, code, reason]);
              }
            },
            cancelOnError: false,
          );
          _subscriptions[wsId] = sub;
        }).catchError((Object error) {
          _pendingWs.remove(wsId);
          if (onErrorRef != null) {
            callbacks.invoke(onErrorRef, [wsId, error.toString()]);
          }
        }),
      );

      ls.pushString(wsId);
      return 1;
    });
    ls.setField(-2, 'connect');

    // websocket.send(wsId, message) -> bool
    ls.pushDartFunction((ls) {
      checkPermission(ls);
      final wsId = ls.checkString(1) ?? '';
      final message = ls.checkString(2) ?? '';
      final ws = _sockets[wsId];
      if (ws == null) {
        ls.pushBoolean(false);
        return 1;
      }

      try {
        ws.add(message);
        ls.pushBoolean(true);
        return 1;
      } catch (_) {
        ls.pushBoolean(false);
        return 1;
      }
    });
    ls.setField(-2, 'send');

    // websocket.close(wsId [, code, reason]) -> bool
    ls.pushDartFunction((ls) {
      checkPermission(ls);
      final wsId = ls.checkString(1) ?? '';
      int? code;
      String? reason;
      if (ls.isInteger(2)) {
        code = ls.toInteger(2);
      }
      if (ls.isString(3)) {
        reason = ls.toStr(3);
      }
      final closed = _closeWs(wsId, code, reason);
      ls.pushBoolean(closed);
      return 1;
    });
    ls.setField(-2, 'close');

    ls.setGlobal('websocket');
  }

  bool _closeWs(String wsId, [int? code, String? reason]) {
    _subscriptions.remove(wsId)?.cancel();
    if (_pendingWs.remove(wsId)) {
      return true;
    }
    final ws = _sockets.remove(wsId);
    if (ws != null) {
      try {
        ws.close(code, reason);
      } catch (_) {}
      return true;
    }
    return false;
  }

  void dispose([LuaCallbackInvoker? callbacks]) {
    for (final sub in _subscriptions.values) {
      sub.cancel();
    }
    _subscriptions.clear();
    for (final ws in _sockets.values) {
      try {
        ws.close();
      } catch (_) {}
    }
    _sockets.clear();

    if (callbacks != null) {
      for (final ref in _callbackRefs) {
        callbacks.release(ref);
      }
    }
    _callbackRefs.clear();
  }
}
