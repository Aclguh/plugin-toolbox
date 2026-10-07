import 'package:lua_dardo/lua.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';

import '../lua_callback_invoker.dart';
import '../lua_engine.dart';
import '../lua_value_codec.dart';

/// `nfc` — 近场通信 (NFC) 标签读写宿主 API。
class NfcApi {
  static void bind(
    LuaState ls,
    PluginContext context,
    LuaHostDelegate delegate,
    LuaCallbackInvoker callbacks,
  ) {
    ls.newTable();

    void checkPermission(LuaState ls) {
      if (!context.hasPermission(PluginPermission.nfc)) {
        ls.error2('权限不足: 插件未声明 nfc 权限');
      }
    }

    // nfc.isAvailable([callback]) -> bool
    ls.pushDartFunction((ls) {
      checkPermission(ls);
      if (ls.type(1) == LuaType.luaFunction) {
        final cbRef = callbacks.ref(1);
        if (cbRef != null) {
          delegate.isNfcAvailable().then((available) {
            callbacks.invokeAndRelease(cbRef, [available]);
          });
        }
        return 0;
      }
      ls.pushBoolean(false);
      return 1;
    });
    ls.setField(-2, 'isAvailable');

    // nfc.readNdef(callback) -> { ok = bool, records = [ { type = str, payload = str } ], error = str? }
    ls.pushDartFunction((ls) {
      checkPermission(ls);
      final cbRef = callbacks.ref(1);
      if (cbRef != null) {
        delegate.readNdef().then((res) {
          if (res != null) {
            callbacks.invokeAndRelease(cbRef, [
              {'ok': true, ...res}
            ]);
          } else {
            callbacks.invokeAndRelease(cbRef, [
              {'ok': false, 'error': '未感应到 NFC 标签或读取超时'}
            ]);
          }
        }).catchError((Object e) {
          callbacks.invokeAndRelease(cbRef, [
            {'ok': false, 'error': e.toString()}
          ]);
        });
      }
      return 0;
    });
    ls.setField(-2, 'readNdef');

    // nfc.writeNdef(recordsList, callback) -> { ok = bool, error = str? }
    ls.pushDartFunction((ls) {
      checkPermission(ls);
      ls.pushValue(1);
      final rawRecords = LuaValueCodec.pop(ls);
      final cbRef = callbacks.ref(2);

      final records = <Map<String, dynamic>>[];
      if (rawRecords is List) {
        for (final item in rawRecords) {
          if (item is Map) {
            records.add(item.cast<String, dynamic>());
          }
        }
      }

      if (cbRef != null) {
        delegate.writeNdef(records).then((success) {
          callbacks.invokeAndRelease(cbRef, [
            {'ok': success, if (!success) 'error': 'NFC 标签写入失败'}
          ]);
        }).catchError((Object e) {
          callbacks.invokeAndRelease(cbRef, [
            {'ok': false, 'error': e.toString()}
          ]);
        });
      }
      return 0;
    });
    ls.setField(-2, 'writeNdef');

    ls.setGlobal('nfc');
  }
}
