import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:lua_dardo/lua.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';

import '../lua_callback_invoker.dart';

/// `socket` — TCP 与 UDP 原生网络套接字 API。
///
/// 严格受限于 `network` 权限，提供 TCP 客户端与 UDP 套接字通信能力，
/// 支持收发文本与十六进制字节流，所有活跃套接字在引擎关闭时自动安全回收。
class SocketApi {
  final Map<String, Socket> _tcpSockets = {};
  final Map<String, StreamSubscription<List<int>>> _tcpSubscriptions = {};
  final Set<String> _pendingTcp = {};
  final Map<String, RawDatagramSocket> _udpSockets = {};
  final Map<String, StreamSubscription<RawSocketEvent>> _udpSubscriptions = {};
  final Set<String> _pendingUdp = {};
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

    // socket.tcpConnect(host, port, optionsTable) -> string (socketId)
    ls.pushDartFunction((ls) {
      checkPermission(ls);
      final host = ls.checkString(1) ?? '';
      final port = ls.checkInteger(2) ?? 0;

      int? onConnectRef;
      int? onDataRef;
      int? onErrorRef;
      int? onCloseRef;
      int timeoutMs = 10000;

      if (ls.type(3) == LuaType.luaTable) {
        ls.getField(3, 'onConnect');
        if (ls.type(-1) == LuaType.luaFunction) {
          onConnectRef = callbacks.ref(-1);
          if (onConnectRef != null) _callbackRefs.add(onConnectRef);
        }
        ls.pop(1);

        ls.getField(3, 'onData');
        if (ls.type(-1) == LuaType.luaFunction) {
          onDataRef = callbacks.ref(-1);
          if (onDataRef != null) _callbackRefs.add(onDataRef);
        }
        ls.pop(1);

        ls.getField(3, 'onError');
        if (ls.type(-1) == LuaType.luaFunction) {
          onErrorRef = callbacks.ref(-1);
          if (onErrorRef != null) _callbackRefs.add(onErrorRef);
        }
        ls.pop(1);

        ls.getField(3, 'onClose');
        if (ls.type(-1) == LuaType.luaFunction) {
          onCloseRef = callbacks.ref(-1);
          if (onCloseRef != null) _callbackRefs.add(onCloseRef);
        }
        ls.pop(1);

        ls.getField(3, 'timeoutMs');
        if (ls.isInteger(-1)) {
          timeoutMs = ls.toInteger(-1);
        }
        ls.pop(1);
      }

      final socketId = 'tcp_${_nextId++}';
      _pendingTcp.add(socketId);

      unawaited(
        Socket.connect(host, port, timeout: Duration(milliseconds: timeoutMs))
            .then((socket) {
          if (!_pendingTcp.remove(socketId)) {
            socket.destroy();
            return;
          }
          _tcpSockets[socketId] = socket;

          if (onConnectRef != null) {
            callbacks.invoke(onConnectRef, [socketId]);
          }

          final sub = socket.listen(
            (data) {
              if (onDataRef != null) {
                final text = utf8.decode(data, allowMalformed: true);
                callbacks.invoke(onDataRef, [socketId, text]);
              }
            },
            onError: (Object error) {
              if (onErrorRef != null) {
                callbacks.invoke(onErrorRef, [socketId, error.toString()]);
              }
            },
            onDone: () {
              _closeTcp(socketId);
              if (onCloseRef != null) {
                callbacks.invoke(onCloseRef, [socketId]);
              }
            },
            cancelOnError: false,
          );
          _tcpSubscriptions[socketId] = sub;
        }).catchError((Object error) {
          _pendingTcp.remove(socketId);
          if (onErrorRef != null) {
            callbacks.invoke(onErrorRef, [socketId, error.toString()]);
          }
        }),
      );

      ls.pushString(socketId);
      return 1;
    });
    ls.setField(-2, 'tcpConnect');

    // socket.tcpSend(socketId, data) -> bool
    ls.pushDartFunction((ls) {
      checkPermission(ls);
      final socketId = ls.checkString(1) ?? '';
      final socket = _tcpSockets[socketId];
      if (socket == null) {
        ls.pushBoolean(false);
        return 1;
      }

      if (ls.isString(2)) {
        final text = ls.toStr(2) ?? '';
        socket.add(utf8.encode(text));
        ls.pushBoolean(true);
        return 1;
      } else if (ls.type(2) == LuaType.luaTable) {
        final bytes = <int>[];
        final len = ls.rawLen(2);
        for (var i = 1; i <= len; i++) {
          ls.rawGetI(2, i);
          if (ls.isInteger(-1)) {
            bytes.add(ls.toInteger(-1));
          }
          ls.pop(1);
        }
        socket.add(bytes);
        ls.pushBoolean(true);
        return 1;
      }

      ls.pushBoolean(false);
      return 1;
    });
    ls.setField(-2, 'tcpSend');

    // socket.tcpClose(socketId) -> bool
    ls.pushDartFunction((ls) {
      checkPermission(ls);
      final socketId = ls.checkString(1) ?? '';
      final closed = _closeTcp(socketId);
      ls.pushBoolean(closed);
      return 1;
    });
    ls.setField(-2, 'tcpClose');

    // socket.udpBind([port], optionsTable) -> string (socketId)
    ls.pushDartFunction((ls) {
      checkPermission(ls);
      int port = 0;
      int optionsIdx = 1;
      if (ls.isInteger(1)) {
        port = ls.toInteger(1);
        optionsIdx = 2;
      }

      int? onDataRef;
      int? onErrorRef;

      if (ls.type(optionsIdx) == LuaType.luaTable) {
        ls.getField(optionsIdx, 'onData');
        if (ls.type(-1) == LuaType.luaFunction) {
          onDataRef = callbacks.ref(-1);
          if (onDataRef != null) _callbackRefs.add(onDataRef);
        }
        ls.pop(1);

        ls.getField(optionsIdx, 'onError');
        if (ls.type(-1) == LuaType.luaFunction) {
          onErrorRef = callbacks.ref(-1);
          if (onErrorRef != null) _callbackRefs.add(onErrorRef);
        }
        ls.pop(1);
      }

      final socketId = 'udp_${_nextId++}';
      _pendingUdp.add(socketId);

      unawaited(
        RawDatagramSocket.bind(InternetAddress.anyIPv4, port).then((socket) {
          if (!_pendingUdp.remove(socketId)) {
            socket.close();
            return;
          }
          _udpSockets[socketId] = socket;

          final sub = socket.listen(
            (event) {
              if (event == RawSocketEvent.read) {
                final datagram = socket.receive();
                if (datagram != null && onDataRef != null) {
                  final text = utf8.decode(datagram.data, allowMalformed: true);
                  callbacks.invoke(onDataRef, [
                    socketId,
                    text,
                    datagram.address.address,
                    datagram.port,
                  ]);
                }
              }
            },
            onError: (Object error) {
              if (onErrorRef != null) {
                callbacks.invoke(onErrorRef, [socketId, error.toString()]);
              }
            },
          );
          _udpSubscriptions[socketId] = sub;
        }).catchError((Object error) {
          _pendingUdp.remove(socketId);
          if (onErrorRef != null) {
            callbacks.invoke(onErrorRef, [socketId, error.toString()]);
          }
        }),
      );

      ls.pushString(socketId);
      return 1;
    });
    ls.setField(-2, 'udpBind');

    // socket.udpSend(socketId, host, port, data) -> bool
    ls.pushDartFunction((ls) {
      checkPermission(ls);
      final socketId = ls.checkString(1) ?? '';
      final host = ls.checkString(2) ?? '';
      final port = ls.checkInteger(3) ?? 0;
      final socket = _udpSockets[socketId];
      if (socket == null) {
        ls.pushBoolean(false);
        return 1;
      }

      final List<int> bytes;
      if (ls.isString(4)) {
        bytes = utf8.encode(ls.toStr(4) ?? '');
      } else if (ls.type(4) == LuaType.luaTable) {
        bytes = <int>[];
        final len = ls.rawLen(4);
        for (var i = 1; i <= len; i++) {
          ls.rawGetI(4, i);
          if (ls.isInteger(-1)) {
            bytes.add(ls.toInteger(-1));
          }
          ls.pop(1);
        }
      } else {
        ls.pushBoolean(false);
        return 1;
      }

      final address = InternetAddress.tryParse(host);
      if (address != null) {
        final sent = socket.send(bytes, address, port);
        ls.pushBoolean(sent > 0);
        return 1;
      } else {
        // 域名解析后发送
        unawaited(
          InternetAddress.lookup(host).then((addresses) {
            if (addresses.isNotEmpty) {
              socket.send(bytes, addresses.first, port);
            }
          }),
        );
        ls.pushBoolean(true);
        return 1;
      }
    });
    ls.setField(-2, 'udpSend');

    // socket.udpClose(socketId) -> bool
    ls.pushDartFunction((ls) {
      checkPermission(ls);
      final socketId = ls.checkString(1) ?? '';
      final closed = _closeUdp(socketId);
      ls.pushBoolean(closed);
      return 1;
    });
    ls.setField(-2, 'udpClose');

    ls.setGlobal('socket');
  }

  bool _closeTcp(String socketId) {
    _tcpSubscriptions.remove(socketId)?.cancel();
    if (_pendingTcp.remove(socketId)) {
      return true;
    }
    final socket = _tcpSockets.remove(socketId);
    if (socket != null) {
      try {
        socket.destroy();
      } catch (_) {}
      return true;
    }
    return false;
  }

  bool _closeUdp(String socketId) {
    _udpSubscriptions.remove(socketId)?.cancel();
    if (_pendingUdp.remove(socketId)) {
      return true;
    }
    final socket = _udpSockets.remove(socketId);
    if (socket != null) {
      try {
        socket.close();
      } catch (_) {}
      return true;
    }
    return false;
  }

  void dispose([LuaCallbackInvoker? callbacks]) {
    for (final sub in _tcpSubscriptions.values) {
      sub.cancel();
    }
    _tcpSubscriptions.clear();
    for (final s in _tcpSockets.values) {
      try {
        s.destroy();
      } catch (_) {}
    }
    _tcpSockets.clear();

    for (final sub in _udpSubscriptions.values) {
      sub.cancel();
    }
    _udpSubscriptions.clear();
    for (final s in _udpSockets.values) {
      try {
        s.close();
      } catch (_) {}
    }
    _udpSockets.clear();

    if (callbacks != null) {
      for (final ref in _callbackRefs) {
        callbacks.release(ref);
      }
    }
    _callbackRefs.clear();
  }
}
