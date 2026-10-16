import 'package:lua_dardo/lua.dart';
import '../lua_engine.dart';
import '../lua_value_codec.dart';

class StateApi {
  static void bind(LuaState ls, LuaHostDelegate delegate) {
    ls.newTable();

    // state.get(key)
    ls.pushDartFunction((ls) {
      final key = ls.checkString(1) ?? '';
      final val = delegate.getState(key);
      LuaValueCodec.push(ls, val);
      return 1;
    });
    ls.setField(-2, 'get');

    // state.set(key, value)
    ls.pushDartFunction((ls) {
      final key = ls.checkString(1) ?? '';
      dynamic val;
      final type = ls.type(2);
      if (type == LuaType.luaTable) {
        val = LuaValueCodec.readTable(ls, 2);
      } else if (type == LuaType.luaBoolean) {
        val = ls.toBoolean(2);
      } else if (type == LuaType.luaNumber) {
        val = ls.isInteger(2) ? ls.toInteger(2) : ls.toNumber(2);
      } else if (type == LuaType.luaString) {
        val = ls.toStr(2);
      } else if (type == LuaType.luaNil) {
        val = null;
      }
      delegate.onStateChanged(key, val);
      return 0;
    });
    ls.setField(-2, 'set');

    ls.setGlobal('state');
  }
}
