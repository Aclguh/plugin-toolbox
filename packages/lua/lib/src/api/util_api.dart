import 'package:lua_dardo/lua.dart';
import 'package:uuid/uuid.dart';

class UtilApi {
  static void bind(LuaState ls) {
    ls.newTable();

    ls.pushDartFunction((ls) {
      ls.pushString(const Uuid().v4());
      return 1;
    });
    ls.setField(-2, 'uuid');

    ls.pushDartFunction((ls) {
      ls.pushInteger(DateTime.now().millisecondsSinceEpoch ~/ 1000);
      return 1;
    });
    ls.setField(-2, 'timestamp');

    ls.pushDartFunction((ls) {
      ls.pushInteger(DateTime.now().millisecondsSinceEpoch);
      return 1;
    });
    ls.setField(-2, 'timestampMs');

    ls.setGlobal('util');
  }
}
