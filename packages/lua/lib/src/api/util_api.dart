import 'package:intl/intl.dart';
import 'package:lua_dardo/lua.dart';
import 'package:uuid/uuid.dart';

class UtilApi {
  static void bind(LuaState ls) {
    ls.newTable();

    // util.uuid() -> string
    ls.pushDartFunction((ls) {
      ls.pushString(const Uuid().v4());
      return 1;
    });
    ls.setField(-2, 'uuid');

    // util.timestamp() -> seconds
    ls.pushDartFunction((ls) {
      ls.pushInteger(DateTime.now().millisecondsSinceEpoch ~/ 1000);
      return 1;
    });
    ls.setField(-2, 'timestamp');

    // util.timestampMs() -> milliseconds
    ls.pushDartFunction((ls) {
      ls.pushInteger(DateTime.now().millisecondsSinceEpoch);
      return 1;
    });
    ls.setField(-2, 'timestampMs');

    // util.formatTime(timestampMs [, pattern]) -> string
    ls.pushDartFunction((ls) {
      final ms = ls.checkInteger(1) ?? 0;
      final pattern = ls.optString(2, 'yyyy-MM-dd HH:mm:ss') ?? 'yyyy-MM-dd HH:mm:ss';
      try {
        final formatted = DateFormat(pattern)
            .format(DateTime.fromMillisecondsSinceEpoch(ms));
        ls.pushString(formatted);
        return 1;
      } catch (e) {
        ls.error2('时间格式化错误: $e');
        return 0;
      }
    });
    ls.setField(-2, 'formatTime');

    // util.parseTime(timeStr [, pattern]) -> timestampMs | nil
    ls.pushDartFunction((ls) {
      final timeStr = ls.checkString(1) ?? '';
      final pattern = ls.optString(2, 'yyyy-MM-dd HH:mm:ss') ?? 'yyyy-MM-dd HH:mm:ss';
      try {
        final dt = DateFormat(pattern).parse(timeStr);
        ls.pushInteger(dt.millisecondsSinceEpoch);
        return 1;
      } catch (e) {
        ls.pushNil();
        return 1;
      }
    });
    ls.setField(-2, 'parseTime');

    ls.setGlobal('util');
  }
}
