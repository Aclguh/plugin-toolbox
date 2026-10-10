import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:lua_dardo/lua.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';

import '../lua_callback_invoker.dart';

/// `network` — 现代 HTTP 网络请求 API。
///
/// 具备完整的 RESTful 请求（GET/POST/PUT/DELETE/REQUEST）、自定义请求头、
/// 独立回调支持与超时控制；同时向后兼容旧版写入全局状态与全局函数机制。
class NetworkApi {
  static void bind(
    LuaState ls,
    PluginContext context,
    LuaCallbackInvoker callbacks,
    void Function(String key, dynamic value) writeState,
  ) {
    ls.newTable();

    void checkPermission(LuaState ls) {
      if (!context.hasPermission(PluginPermission.network)) {
        ls.error2('权限不足: 插件未声明 network 权限');
      }
    }

    Map<String, String> parseHeaders(LuaState ls, int idx) {
      final headers = <String, String>{};
      if (ls.type(idx) == LuaType.luaTable) {
        ls.pushNil();
        while (ls.next(idx)) {
          final k = ls.toStr(-2);
          final v = ls.toStr(-1);
          if (k != null && v != null) {
            headers[k] = v;
          }
          ls.pop(1);
        }
      }
      return headers;
    }

    void handleResponse(
      http.Response response,
      int? cbRef,
    ) {
      if (cbRef != null) {
        callbacks.invokeAndRelease(cbRef, [
          {
            'ok': response.statusCode >= 200 && response.statusCode < 300,
            'status': response.statusCode,
            'body': response.body,
            'headers': response.headers,
          }
        ]);
      } else {
        writeState('__http_status', response.statusCode);
        writeState('__http_body', response.body);
        callbacks.invokeGlobal('onNetworkResponse', [
          response.statusCode,
          response.body,
        ]);
      }
    }

    void handleError(
      Object error,
      int? cbRef,
    ) {
      final errorMsg = error.toString();
      if (cbRef != null) {
        callbacks.invokeAndRelease(cbRef, [
          {
            'ok': false,
            'status': 0,
            'body': '',
            'headers': <String, String>{},
            'error': errorMsg,
          }
        ]);
      } else {
        writeState('__http_error', errorMsg);
        callbacks.invokeGlobal('onNetworkError', [errorMsg]);
      }
    }

    // network.get(url [, headers | callback, callback])
    ls.pushDartFunction((ls) {
      checkPermission(ls);
      final url = ls.checkString(1) ?? '';
      Map<String, String>? headers;
      int? cbRef;

      if (ls.type(2) == LuaType.luaFunction) {
        cbRef = callbacks.ref(2);
      } else if (ls.type(2) == LuaType.luaTable) {
        headers = parseHeaders(ls, 2);
        if (ls.type(3) == LuaType.luaFunction) {
          cbRef = callbacks.ref(3);
        }
      }

      final Uri uri;
      try {
        uri = Uri.parse(url);
      } on FormatException catch (e) {
        ls.error2('URL 不合法: $e');
        return 0;
      }

      if (!context.isHostAllowed(uri.host)) {
        handleError('域名不在白名单内: ${uri.host}', cbRef);
        return 0;
      }

      unawaited(
        http.get(uri, headers: headers).then((response) {
          handleResponse(response, cbRef);
        }).catchError((Object e) {
          handleError(e, cbRef);
        }),
      );
      return 0;
    });
    ls.setField(-2, 'get');

    // network.post(url, body [, contentType | headers | callback, callback])
    ls.pushDartFunction((ls) {
      checkPermission(ls);
      final url = ls.checkString(1) ?? '';
      final body = ls.checkString(2) ?? '';
      Map<String, String> headers = {'Content-Type': 'application/json'};
      int? cbRef;

      if (ls.type(3) == LuaType.luaFunction) {
        cbRef = callbacks.ref(3);
      } else if (ls.type(3) == LuaType.luaString) {
        final ct = ls.toStr(3) ?? 'application/json';
        headers['Content-Type'] = ct;
        if (ls.type(4) == LuaType.luaFunction) {
          cbRef = callbacks.ref(4);
        }
      } else if (ls.type(3) == LuaType.luaTable) {
        headers = parseHeaders(ls, 3);
        if (ls.type(4) == LuaType.luaFunction) {
          cbRef = callbacks.ref(4);
        }
      }

      final Uri uri;
      try {
        uri = Uri.parse(url);
      } on FormatException catch (e) {
        ls.error2('URL 不合法: $e');
        return 0;
      }

      if (!context.isHostAllowed(uri.host)) {
        handleError('域名不在白名单内: ${uri.host}', cbRef);
        return 0;
      }

      unawaited(
        http.post(uri, headers: headers, body: body).then((response) {
          handleResponse(response, cbRef);
        }).catchError((Object e) {
          handleError(e, cbRef);
        }),
      );
      return 0;
    });
    ls.setField(-2, 'post');

    // network.put(url, body [, headers, callback])
    ls.pushDartFunction((ls) {
      checkPermission(ls);
      final url = ls.checkString(1) ?? '';
      final body = ls.checkString(2) ?? '';
      Map<String, String> headers = {'Content-Type': 'application/json'};
      int? cbRef;

      if (ls.type(3) == LuaType.luaFunction) {
        cbRef = callbacks.ref(3);
      } else if (ls.type(3) == LuaType.luaTable) {
        headers = parseHeaders(ls, 3);
        if (ls.type(4) == LuaType.luaFunction) {
          cbRef = callbacks.ref(4);
        }
      }

      final Uri uri;
      try {
        uri = Uri.parse(url);
      } on FormatException catch (e) {
        ls.error2('URL 不合法: $e');
        return 0;
      }

      if (!context.isHostAllowed(uri.host)) {
        handleError('域名不在白名单内: ${uri.host}', cbRef);
        return 0;
      }

      unawaited(
        http.put(uri, headers: headers, body: body).then((response) {
          handleResponse(response, cbRef);
        }).catchError((Object e) {
          handleError(e, cbRef);
        }),
      );
      return 0;
    });
    ls.setField(-2, 'put');

    // network.delete(url [, headers, callback])
    ls.pushDartFunction((ls) {
      checkPermission(ls);
      final url = ls.checkString(1) ?? '';
      Map<String, String>? headers;
      int? cbRef;

      if (ls.type(2) == LuaType.luaFunction) {
        cbRef = callbacks.ref(2);
      } else if (ls.type(2) == LuaType.luaTable) {
        headers = parseHeaders(ls, 2);
        if (ls.type(3) == LuaType.luaFunction) {
          cbRef = callbacks.ref(3);
        }
      }

      final Uri uri;
      try {
        uri = Uri.parse(url);
      } on FormatException catch (e) {
        ls.error2('URL 不合法: $e');
        return 0;
      }

      if (!context.isHostAllowed(uri.host)) {
        handleError('域名不在白名单内: ${uri.host}', cbRef);
        return 0;
      }

      unawaited(
        http.delete(uri, headers: headers).then((response) {
          handleResponse(response, cbRef);
        }).catchError((Object e) {
          handleError(e, cbRef);
        }),
      );
      return 0;
    });
    ls.setField(-2, 'delete');

    // network.request(configTable [, callback])
    ls.pushDartFunction((ls) {
      checkPermission(ls);
      if (ls.type(1) != LuaType.luaTable) {
        ls.error2('network.request: 第一个参数必须为配置表');
        return 0;
      }

      String url = '';
      String method = 'GET';
      Map<String, String> headers = {};
      String? body;
      int timeoutMs = 15000;

      ls.getField(1, 'url');
      if (ls.isString(-1)) url = ls.toStr(-1) ?? '';
      ls.pop(1);

      ls.getField(1, 'method');
      if (ls.isString(-1)) method = (ls.toStr(-1) ?? 'GET').toUpperCase();
      ls.pop(1);

      ls.getField(1, 'headers');
      if (ls.type(-1) == LuaType.luaTable) {
        headers = parseHeaders(ls, -1);
      }
      ls.pop(1);

      ls.getField(1, 'body');
      if (ls.isString(-1)) body = ls.toStr(-1);
      ls.pop(1);

      ls.getField(1, 'timeoutMs');
      if (ls.isInteger(-1)) timeoutMs = ls.toInteger(-1);
      ls.pop(1);

      final cbRef = callbacks.ref(2);

      final Uri uri;
      try {
        uri = Uri.parse(url);
      } on FormatException catch (e) {
        ls.error2('URL 不合法: $e');
        return 0;
      }

      if (!context.isHostAllowed(uri.host)) {
        handleError('域名不在白名单内: ${uri.host}', cbRef);
        return 0;
      }

      final req = http.Request(method, uri);
      req.headers.addAll(headers);
      if (body != null) {
        req.body = body;
      }

      unawaited(
        http.Client()
            .send(req)
            .then(http.Response.fromStream)
            .timeout(Duration(milliseconds: timeoutMs))
            .then((res) {
          handleResponse(res, cbRef);
        }).catchError((Object e) {
          handleError(e, cbRef);
        }),
      );
      return 0;
    });
    ls.setField(-2, 'request');

    // network.resolveDns(host [, callback])
    ls.pushDartFunction((ls) {
      checkPermission(ls);
      final host = ls.checkString(1) ?? '';
      final cbRef = callbacks.ref(2);

      if (!context.isHostAllowed(host)) {
        if (cbRef != null) {
          callbacks.invokeAndRelease(cbRef, [
            {
              'ok': false,
              'host': host,
              'addresses': <String>[],
              'error': '域名不在白名单内: $host',
            }
          ]);
        } else {
          writeState('__dns_error', '域名不在白名单内: $host');
        }
        return 0;
      }

      unawaited(
        InternetAddress.lookup(host).then((addresses) {
          final ipList = addresses.map((a) => a.address).toList();
          if (cbRef != null) {
            callbacks.invokeAndRelease(cbRef, [
              {
                'ok': true,
                'host': host,
                'addresses': ipList,
              }
            ]);
          } else {
            writeState('__dns_result', ipList);
          }
        }).catchError((Object error) {
          if (cbRef != null) {
            callbacks.invokeAndRelease(cbRef, [
              {
                'ok': false,
                'host': host,
                'addresses': <String>[],
                'error': error.toString(),
              }
            ]);
          } else {
            writeState('__dns_error', error.toString());
          }
        }),
      );
      return 0;
    });
    ls.setField(-2, 'resolveDns');

    // network.ping(host [, optionsTable | callback, callback])
    ls.pushDartFunction((ls) {
      checkPermission(ls);
      final host = ls.checkString(1) ?? '';
      int port = 80;
      int timeoutMs = 3000;
      int? cbRef;

      if (ls.type(2) == LuaType.luaFunction) {
        cbRef = callbacks.ref(2);
      } else if (ls.type(2) == LuaType.luaTable) {
        ls.getField(2, 'port');
        if (ls.isInteger(-1)) port = ls.toInteger(-1);
        ls.pop(1);

        ls.getField(2, 'timeoutMs');
        if (ls.isInteger(-1)) timeoutMs = ls.toInteger(-1);
        ls.pop(1);

        if (ls.type(3) == LuaType.luaFunction) {
          cbRef = callbacks.ref(3);
        }
      }

      if (!context.isHostAllowed(host)) {
        if (cbRef != null) {
          callbacks.invokeAndRelease(cbRef, [
            {
              'ok': false,
              'host': host,
              'port': port,
              'reachable': false,
              'error': '域名不在白名单内: $host',
            }
          ]);
        }
        return 0;
      }

      final stopwatch = Stopwatch()..start();
      unawaited(
        Socket.connect(host, port, timeout: Duration(milliseconds: timeoutMs))
            .then((socket) {
          stopwatch.stop();
          final ip = socket.remoteAddress.address;
          socket.destroy();
          if (cbRef != null) {
            callbacks.invokeAndRelease(cbRef, [
              {
                'ok': true,
                'host': host,
                'ip': ip,
                'port': port,
                'latencyMs': stopwatch.elapsedMilliseconds,
                'reachable': true,
              }
            ]);
          }
        }).catchError((Object error) {
          stopwatch.stop();
          if (cbRef != null) {
            callbacks.invokeAndRelease(cbRef, [
              {
                'ok': false,
                'host': host,
                'port': port,
                'reachable': false,
                'error': error.toString(),
              }
            ]);
          }
        }),
      );
      return 0;
    });
    ls.setField(-2, 'ping');

    // network.scanPort(host, port [, timeoutMs | callback, callback])
    ls.pushDartFunction((ls) {
      checkPermission(ls);
      final host = ls.checkString(1) ?? '';
      final port = ls.checkInteger(2) ?? 0;
      int timeoutMs = 2000;
      int? cbRef;

      if (ls.type(3) == LuaType.luaFunction) {
        cbRef = callbacks.ref(3);
      } else if (ls.isInteger(3)) {
        timeoutMs = ls.toInteger(3);
        if (ls.type(4) == LuaType.luaFunction) {
          cbRef = callbacks.ref(4);
        }
      }

      if (!context.isHostAllowed(host)) {
        if (cbRef != null) {
          callbacks.invokeAndRelease(cbRef, [
            {
              'host': host,
              'port': port,
              'open': false,
              'latencyMs': 0,
              'error': '域名不在白名单内: $host',
            }
          ]);
        }
        return 0;
      }

      final stopwatch = Stopwatch()..start();
      unawaited(
        Socket.connect(host, port, timeout: Duration(milliseconds: timeoutMs))
            .then((socket) {
          stopwatch.stop();
          socket.destroy();
          if (cbRef != null) {
            callbacks.invokeAndRelease(cbRef, [
              {
                'host': host,
                'port': port,
                'open': true,
                'latencyMs': stopwatch.elapsedMilliseconds,
              }
            ]);
          }
        }).catchError((_) {
          stopwatch.stop();
          if (cbRef != null) {
            callbacks.invokeAndRelease(cbRef, [
              {
                'host': host,
                'port': port,
                'open': false,
                'latencyMs': stopwatch.elapsedMilliseconds,
              }
            ]);
          }
        }),
      );
      return 0;
    });
    ls.setField(-2, 'scanPort');

    ls.setGlobal('network');
  }
}
