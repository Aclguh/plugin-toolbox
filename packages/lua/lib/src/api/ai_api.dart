import 'package:lua_dardo/lua.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';

import '../lua_callback_invoker.dart';
import '../lua_engine.dart';
import '../lua_value_codec.dart';

/// `ai` — 宿主统一大语言模型 AI 网关宿主 API。
class AiApi {
  static void bind(
    LuaState ls,
    PluginContext context,
    LuaHostDelegate delegate,
    LuaCallbackInvoker callbacks,
  ) {
    ls.newTable();

    void checkPermission(LuaState ls) {
      if (!context.hasPermission(PluginPermission.ai)) {
        ls.error2('权限不足: 插件未声明 ai 权限');
      }
    }

    // ai.isAvailable([callback]) -> bool
    ls.pushDartFunction((ls) {
      checkPermission(ls);
      if (ls.type(1) == LuaType.luaFunction) {
        final cbRef = callbacks.ref(1);
        if (cbRef != null) {
          delegate.isAiAvailable().then((available) {
            callbacks.invokeAndRelease(cbRef, [available]);
          });
        }
        return 0;
      }
      ls.pushBoolean(false);
      return 1;
    });
    ls.setField(-2, 'isAvailable');

    // ai.chat(requestTable, callback)
    // requestTable: { messages = { { role = "user", content = "..." } }, model = "...", temperature = 0.7 }
    ls.pushDartFunction((ls) {
      checkPermission(ls);
      ls.pushValue(1);
      final rawReq = LuaValueCodec.pop(ls);
      final cbRef = callbacks.ref(2);

      if (rawReq is! Map) {
        if (cbRef != null) {
          callbacks.invokeAndRelease(cbRef, [
            {'ok': false, 'error': 'ai.chat 请求参数必须为对象字典'}
          ]);
        }
        return 0;
      }

      final messages = <Map<String, dynamic>>[];
      final rawMessages = rawReq['messages'];
      if (rawMessages is List) {
        for (final m in rawMessages) {
          if (m is Map) {
            messages.add(m.cast<String, dynamic>());
          }
        }
      }

      final model = rawReq['model']?.toString();
      final temperature = (rawReq['temperature'] as num?)?.toDouble();

      if (cbRef != null) {
        delegate
            .aiChat(messages: messages, model: model, temperature: temperature)
            .then((res) {
          callbacks.invokeAndRelease(cbRef, [res]);
        }).catchError((Object e) {
          callbacks.invokeAndRelease(cbRef, [
            {'ok': false, 'error': e.toString()}
          ]);
        });
      }
      return 0;
    });
    ls.setField(-2, 'chat');

    // ai.streamChat(requestTable, onChunk [, onDone [, onError]])
    ls.pushDartFunction((ls) {
      checkPermission(ls);
      ls.pushValue(1);
      final rawReq = LuaValueCodec.pop(ls);
      final chunkCbRef = callbacks.ref(2);
      final doneCbRef =
          ls.type(3) == LuaType.luaFunction ? callbacks.ref(3) : null;
      final errorCbRef =
          ls.type(4) == LuaType.luaFunction ? callbacks.ref(4) : null;

      if (rawReq is! Map) {
        if (errorCbRef != null) {
          callbacks.invokeAndRelease(errorCbRef, ['请求参数必须为字典']);
        }
        return 0;
      }

      final messages = <Map<String, dynamic>>[];
      final rawMessages = rawReq['messages'];
      if (rawMessages is List) {
        for (final m in rawMessages) {
          if (m is Map) {
            messages.add(m.cast<String, dynamic>());
          }
        }
      }

      final model = rawReq['model']?.toString();
      final temperature = (rawReq['temperature'] as num?)?.toDouble();

      final stream = delegate.aiStreamChat(
        messages: messages,
        model: model,
        temperature: temperature,
      );

      stream.listen(
        (chunk) {
          if (chunkCbRef != null) {
            callbacks.invoke(chunkCbRef, [chunk]);
          }
        },
        onDone: () {
          if (chunkCbRef != null) {
            callbacks.release(chunkCbRef);
          }
          if (doneCbRef != null) {
            callbacks.invokeAndRelease(doneCbRef, []);
          }
        },
        onError: (Object e) {
          if (chunkCbRef != null) {
            callbacks.release(chunkCbRef);
          }
          if (errorCbRef != null) {
            callbacks.invokeAndRelease(errorCbRef, [e.toString()]);
          }
        },
      );

      return 0;
    });
    ls.setField(-2, 'streamChat');

    ls.setGlobal('ai');
  }
}
