import 'package:lua_dardo/lua.dart';
import '../lua_engine.dart';
import 'api_guard.dart';

/// `haptic` — 设备触觉震动反馈 API。
///
/// 提供不同强度的系统触觉反馈，为计算器、开关、按钮点击等场景提供细腻交互。
class HapticApi {
  static void bind(LuaState ls, LuaHostDelegate delegate) {
    ls.newTable();

    void bindMethod(String name, HapticType type) {
      ls.pushDartFunction((ls) {
        delegate.hapticFeedback(type.name);
        return 0;
      });
      ls.setField(-2, name);
    }

    bindMethod('light', HapticType.light);
    bindMethod('medium', HapticType.medium);
    bindMethod('heavy', HapticType.heavy);
    bindMethod('selection', HapticType.selection);
    bindMethod('vibrate', HapticType.vibrate);

    ls.setGlobal('haptic');
  }
}
