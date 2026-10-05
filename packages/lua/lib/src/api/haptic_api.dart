import 'package:lua_dardo/lua.dart';
import '../lua_engine.dart';

/// `haptic` — 设备触觉震动反馈 API。
///
/// 提供不同强度的系统触觉反馈，为计算器、开关、按钮点击等场景提供细腻交互。
class HapticApi {
  static void bind(LuaState ls, LuaHostDelegate delegate) {
    ls.newTable();

    void bindMethod(String name, String type) {
      ls.pushDartFunction((ls) {
        delegate.hapticFeedback(type);
        return 0;
      });
      ls.setField(-2, name);
    }

    bindMethod('light', 'light');
    bindMethod('medium', 'medium');
    bindMethod('heavy', 'heavy');
    bindMethod('selection', 'selection');
    bindMethod('vibrate', 'vibrate');

    ls.setGlobal('haptic');
  }
}
