import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:lua_dardo/lua.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';

import '../delegates/domain_delegates.dart';
import '../lua_callback_invoker.dart';

/// `network` — 现代 HTTP 网络请求 API。
///
/// 具备完整的 RESTful 请求（GET/POST/PUT/DELETE/REQUEST）、自定义请求头、
/// 独立回调支持与超时控制；同时向后兼容旧版写入全局状态与全局函数机制。
class NetworkApi {
  /// 单次请求默认超时（各 I/O 阶段独立计时）
  static const int defaultTimeoutMs = 15000;

  /// 302 等重定向的最大跟随跳数；每跳目标 host 都重新走白名单校验，
  /// 防止白名单域被利用作跳板跳转至任意外域
  static const int maxRedirectHops = 5;

  /// 响应体大小上限（10MB），恶意服务端无限输出不得耗尽宿主内存
  static const int maxResponseBytes = 10 * 1024 * 1024;

  /// 判断指定主机名或 IP 是否属于回环或私有局域网地址
  static bool isPrivateOrLocalHost(String host) {
    var normalized = host.trim().toLowerCase();
    if (normalized.startsWith('[') && normalized.contains(']')) {
      normalized = normalized.substring(1, normalized.indexOf(']'));
    } else if (normalized.contains(':') &&
        !normalized.contains('::') &&
        normalized.split(':').length == 2) {
      // 仅针对非 IPv6 的 host:port 剥离端口号
      normalized = normalized.split(':').first;
    }
    if (normalized.isEmpty) return false;

    if (normalized == 'localhost' ||
        normalized.endsWith('.localhost') ||
        normalized.endsWith('.local') ||
        normalized.endsWith('.internal') ||
        normalized.endsWith('.lan')) {
      return true;
    }

    final addr = InternetAddress.tryParse(normalized);
    if (addr != null) {
      if (addr.isLoopback || addr.isLinkLocal) return true;
      final raw = addr.rawAddress;
      if (addr.type == InternetAddressType.IPv4) {
        final b0 = raw[0];
        final b1 = raw[1];
        if (b0 == 0) return true; // 0.0.0.0/8
        if (b0 == 10) return true; // 10.0.0.0/8
        if (b0 == 127) return true; // 127.0.0.0/8
        if (b0 == 169 && b1 == 254) return true; // 169.254.0.0/16
        if (b0 == 172 && (b1 >= 16 && b1 <= 31)) return true; // 172.16.0.0/12
        if (b0 == 192 && b1 == 168) return true; // 192.168.0.0/16
        if (b0 == 255 && b1 == 255 && raw[2] == 255 && raw[3] == 255) {
          return true;
        }
      } else if (addr.type == InternetAddressType.IPv6) {
        // Unique Local Address (ULA): fc00::/7 (0xfc or 0xfd)
        if (raw[0] == 0xfc || raw[0] == 0xfd) return true;
        // IPv4-mapped IPv6: ::ffff:w.x.y.z
        if (raw.length == 16) {
          var isMapped = true;
          for (var i = 0; i < 10; i++) {
            if (raw[i] != 0) {
              isMapped = false;
              break;
            }
          }
          if (isMapped && raw[10] == 0xff && raw[11] == 0xff) {
            final b0 = raw[12];
            final b1 = raw[13];
            if (b0 == 0 || b0 == 10 || b0 == 127) return true;
            if (b0 == 169 && b1 == 254) return true;
            if (b0 == 172 && (b1 >= 16 && b1 <= 31)) return true;
            if (b0 == 192 && b1 == 168) return true;
          }
        }
      }
    }

    return false;
  }

  /// 综合白名单与 SSRF 防护校验
  ///
  /// 对于私有/回环地址，仅在 allowedDomains 显式声明该精确主机（而非通配符 '*'）时放行；
  /// 未配置白名单或仅配置 '*' 时一律拦截。
  static bool isHostAllowedWithSsrfCheck(PluginContext context, String host) {
    if (!context.isHostAllowed(host)) {
      return false;
    }
    if (isPrivateOrLocalHost(host)) {
      final allowed = context.allowedDomains;
      if (allowed == null || allowed.isEmpty) return false;
      var normalized = host.trim().toLowerCase();
      if (normalized.startsWith('[') && normalized.contains(']')) {
        normalized = normalized.substring(1, normalized.indexOf(']'));
      } else if (normalized.contains(':')) {
        normalized = normalized.split(':').first;
      }
      return allowed.any((pattern) {
        final p = pattern.trim().toLowerCase();
        return p == normalized && p != '*';
      });
    }
    return true;
  }

  /// 可注入的 DNS 解析函数，供单元测试模拟 DNS 重绑定场景
  static Future<List<InternetAddress>> Function(String host) dnsLookup =
      InternetAddress.lookup;

  /// 异步 DNS 解析与防 DNS 重绑定校验：
  /// 若目标 Host 为域名，执行 DNS 查询；
  /// 若解析出的任一 IP 地址属于私有/环回/链路本地地址，且未在 allowedDomains 显式放行，则拒绝连接。
  static Future<bool> checkDnsResolutionSafety(
    PluginContext context,
    String host,
  ) async {
    final directIp = InternetAddress.tryParse(host.trim());
    if (directIp != null) {
      return isHostAllowedWithSsrfCheck(context, host);
    }

    try {
      final addresses =
          await dnsLookup(host).timeout(const Duration(seconds: 5));
      if (addresses.isEmpty) return false;
      for (final addr in addresses) {
        if (isPrivateOrLocalHost(addr.address)) {
          final allowed = context.allowedDomains;
          if (allowed == null || allowed.isEmpty) return false;
          final normalized = addr.address.trim().toLowerCase();
          final isExplicitlyAllowed = allowed.any((p) {
            final pattern = p.trim().toLowerCase();
            return pattern == normalized && pattern != '*';
          });
          if (!isExplicitlyAllowed) {
            return false;
          }
        }
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  static void bind(
    LuaState ls,
    PluginContext context,
    LuaCallbackInvoker callbacks,
    void Function(String key, dynamic value) writeState, [
    LuaHostDelegate? delegate,
  ]) {
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

    // 读取响应流并施加大小上限：预检 contentLength，读取中实时截断保护
    Future<List<int>> readLimited(
        http.ByteStream stream, int? declaredLength, int timeoutMs) async {
      if (declaredLength != null && declaredLength > maxResponseBytes) {
        await stream.drain<void>();
        throw Exception('响应体超出大小上限 (${maxResponseBytes ~/ (1024 * 1024)}MB)');
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk
          in stream.timeout(Duration(milliseconds: timeoutMs))) {
        if (builder.length + chunk.length > maxResponseBytes) {
          throw Exception('响应体超出大小上限 (${maxResponseBytes ~/ (1024 * 1024)}MB)');
        }
        builder.add(chunk);
      }
      return builder.takeBytes();
    }

    // 禁用自动重定向的统一请求入口：收到 3xx 时逐跳解析 Location，
    // 每跳目标 host 重新过白名单后才继续请求，并对响应体施加大小上限。
    Future<http.Response> sendChecked(
      String method,
      Uri uri,
      Map<String, String> headers,
      String? body,
      int timeoutMs,
    ) async {
      var currentUri = uri;
      var currentMethod = method.toUpperCase();
      var currentHeaders = Map<String, String>.of(headers);
      String? currentBody = body;
      final client = http.Client();
      try {
        for (var hop = 0;; hop++) {
          final isDnsSafe =
              await checkDnsResolutionSafety(context, currentUri.host);
          if (!isDnsSafe) {
            throw Exception(
                '目标地址解析至私有网段被拦截 (DNS Rebinding 防护): ${currentUri.host}');
          }

          final req = http.Request(currentMethod, currentUri)
            ..followRedirects = false
            ..maxRedirects = 0
            ..headers.addAll(currentHeaders);
          if (currentBody != null &&
              currentMethod != 'GET' &&
              currentMethod != 'HEAD') {
            req.body = currentBody;
          }

          final streamed =
              await client.send(req).timeout(Duration(milliseconds: timeoutMs));
          final status = streamed.statusCode;
          final isRedirect = status == 301 ||
              status == 302 ||
              status == 303 ||
              status == 307 ||
              status == 308;
          final location = streamed.headers['location'];

          if (isRedirect && location != null && location.isNotEmpty) {
            await streamed.stream.drain<void>();
            if (hop >= maxRedirectHops) {
              throw Exception('重定向跳数超限 (>$maxRedirectHops)');
            }
            final nextUri = currentUri.resolve(location);
            if (!context.isHostAllowed(nextUri.host)) {
              throw Exception('重定向目标域名不在白名单内: ${nextUri.host}');
            }
            if (!isHostAllowedWithSsrfCheck(context, nextUri.host)) {
              throw Exception('重定向目标为私有地址被拦截 (SSRF 防护): ${nextUri.host}');
            }
            if (!await checkDnsResolutionSafety(context, nextUri.host)) {
              throw Exception(
                  '重定向目标解析至私有网段被拦截 (DNS Rebinding 防护): ${nextUri.host}');
            }
            // 303（及浏览器惯例的 301/302 非 GET）改写为 GET 并丢弃请求体
            if (status == 303 ||
                ((status == 301 || status == 302) &&
                    currentMethod != 'GET' &&
                    currentMethod != 'HEAD')) {
              currentMethod = 'GET';
              currentBody = null;
              currentHeaders = Map.of(currentHeaders)
                ..removeWhere((k, v) =>
                    k.toLowerCase() == 'content-type' ||
                    k.toLowerCase() == 'content-length');
            }
            currentUri = nextUri;
            continue;
          }

          final bodyBytes = await readLimited(
              streamed.stream, streamed.contentLength, timeoutMs);
          return http.Response.bytes(
            bodyBytes,
            status,
            request: streamed.request,
            headers: streamed.headers,
            isRedirect: streamed.isRedirect,
            persistentConnection: streamed.persistentConnection,
            reasonPhrase: streamed.reasonPhrase,
          );
        }
      } finally {
        client.close();
      }
    }

    // 解析 URL 并过首跳白名单后派发请求（get/post/put/delete/request 共用）
    void dispatch(
      LuaState ls, {
      required String method,
      required String url,
      Map<String, String> headers = const {},
      String? body,
      int timeoutMs = defaultTimeoutMs,
      int? cbRef,
    }) {
      final Uri uri;
      try {
        uri = Uri.parse(url);
      } on FormatException catch (e) {
        ls.error2('URL 不合法: $e');
        return;
      }

      if (!context.isHostAllowed(uri.host)) {
        handleError('域名不在白名单内: ${uri.host}', cbRef);
        return;
      }

      if (!isHostAllowedWithSsrfCheck(context, uri.host)) {
        handleError('禁止访问局域网或本地私有地址 (SSRF 防护): ${uri.host}', cbRef);
        return;
      }

      unawaited(
        sendChecked(method, uri, headers, body, timeoutMs).then((response) {
          handleResponse(response, cbRef);
        }).catchError((Object e) {
          handleError(e, cbRef);
        }),
      );
    }

    // network.get(url [, headers | callback, callback])
    ls.pushDartFunction((ls) {
      checkPermission(ls);
      final url = ls.checkString(1) ?? '';
      Map<String, String> headers = const {};
      int? cbRef;

      if (ls.type(2) == LuaType.luaFunction) {
        cbRef = callbacks.ref(2);
      } else if (ls.type(2) == LuaType.luaTable) {
        headers = parseHeaders(ls, 2);
        if (ls.type(3) == LuaType.luaFunction) {
          cbRef = callbacks.ref(3);
        }
      }

      dispatch(ls, method: 'GET', url: url, headers: headers, cbRef: cbRef);
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

      dispatch(ls,
          method: 'POST', url: url, headers: headers, body: body, cbRef: cbRef);
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

      dispatch(ls,
          method: 'PUT', url: url, headers: headers, body: body, cbRef: cbRef);
      return 0;
    });
    ls.setField(-2, 'put');

    // network.delete(url [, headers, callback])
    ls.pushDartFunction((ls) {
      checkPermission(ls);
      final url = ls.checkString(1) ?? '';
      Map<String, String> headers = const {};
      int? cbRef;

      if (ls.type(2) == LuaType.luaFunction) {
        cbRef = callbacks.ref(2);
      } else if (ls.type(2) == LuaType.luaTable) {
        headers = parseHeaders(ls, 2);
        if (ls.type(3) == LuaType.luaFunction) {
          cbRef = callbacks.ref(3);
        }
      }

      dispatch(ls, method: 'DELETE', url: url, headers: headers, cbRef: cbRef);
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
      int timeoutMs = defaultTimeoutMs;

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

      dispatch(
        ls,
        method: method,
        url: url,
        headers: headers,
        body: body,
        timeoutMs: timeoutMs,
        cbRef: cbRef,
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

    // network.getWifiInfo([callback]) -> table { ssid, bssid, rssi, ip }
    ls.pushDartFunction((ls) {
      checkPermission(ls);
      int? cbRef;
      if (ls.type(1) == LuaType.luaFunction) {
        cbRef = callbacks.ref(1);
      }

      if (delegate != null) {
        unawaited(
          delegate.getWifiInfo().then((info) {
            if (cbRef != null) {
              callbacks.invokeAndRelease(cbRef, [info]);
            } else {
              writeState('__wifi_info', info);
            }
          }).catchError((Object _) {
            if (cbRef != null) {
              callbacks.invokeAndRelease(cbRef, [null]);
            } else {
              writeState('__wifi_info', null);
            }
          }),
        );
      } else {
        if (cbRef != null) {
          callbacks.invokeAndRelease(cbRef, [null]);
        }
      }
      return 0;
    });
    ls.setField(-2, 'getWifiInfo');

    ls.setGlobal('network');
  }
}
