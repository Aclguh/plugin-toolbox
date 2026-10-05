import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:lua_dardo/lua.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';

import '../lua_callback_invoker.dart';

class NetworkApi {
  /// 异步响应无法在 Lua 同步栈中直接返回：结果统一写入状态
  /// （`__http_status` / `__http_body` / `__http_error`），并回调脚本定义的
  /// 全局函数 `onNetworkResponse(status, body)` / `onNetworkError(message)`。
  static void bind(
    LuaState ls,
    PluginContext context,
    LuaCallbackInvoker callbacks,
    void Function(String key, dynamic value) writeState,
  ) {
    ls.newTable();

    // network.get(url)
    ls.pushDartFunction((ls) {
      if (!context.hasPermission(PluginPermission.network)) {
        ls.error2('权限不足: 插件未声明 network 权限');
        return 0;
      }
      final url = ls.checkString(1) ?? '';
      final Uri uri;
      try {
        uri = Uri.parse(url);
      } on FormatException catch (e) {
        ls.error2('URL 不合法: $e');
        return 0;
      }
      // .then 内的异常不会被外层 try-catch 捕获，必须自带 catchError 兜底
      unawaited(
        http.get(uri).then((response) {
          writeState('__http_status', response.statusCode);
          writeState('__http_body', response.body);
          callbacks.invokeGlobal('onNetworkResponse', [
            response.statusCode,
            response.body,
          ]);
        }).catchError((Object e) {
          writeState('__http_error', e.toString());
          callbacks.invokeGlobal('onNetworkError', [e.toString()]);
        }),
      );
      return 0;
    });
    ls.setField(-2, 'get');

    // network.post(url, body, [contentType]) — 请求体为文本，Content-Type 默认 application/json
    ls.pushDartFunction((ls) {
      if (!context.hasPermission(PluginPermission.network)) {
        ls.error2('权限不足: 插件未声明 network 权限');
        return 0;
      }
      final url = ls.checkString(1) ?? '';
      final body = ls.checkString(2) ?? '';
      final contentType = ls.optString(3, 'application/json') ?? 'application/json';
      final Uri uri;
      try {
        uri = Uri.parse(url);
      } on FormatException catch (e) {
        ls.error2('URL 不合法: $e');
        return 0;
      }
      // .then 内的异常不会被外层 try-catch 捕获，必须自带 catchError 兜底
      unawaited(
        http
            .post(uri, headers: {'Content-Type': contentType}, body: body)
            .then((response) {
          writeState('__http_status', response.statusCode);
          writeState('__http_body', response.body);
          callbacks.invokeGlobal('onNetworkResponse', [
            response.statusCode,
            response.body,
          ]);
        }).catchError((Object e) {
          writeState('__http_error', e.toString());
          callbacks.invokeGlobal('onNetworkError', [e.toString()]);
        }),
      );
      return 0;
    });
    ls.setField(-2, 'post');

    ls.setGlobal('network');
  }
}
