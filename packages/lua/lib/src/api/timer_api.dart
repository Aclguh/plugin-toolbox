import 'dart:async';
import 'package:lua_dardo/lua.dart';
import '../lua_callback_invoker.dart';

/// `timer` — 运行时定时调度 API。
///
/// 弥补 Lua 缺少原生异步定时的缺陷，支持倒计时、周期心跳与延迟任务。
/// 由宿主统一管理句柄并在引擎关闭时注销，杜绝后台内存泄漏。
class TimerApi {
  final Map<int, Timer> _activeTimers = {};
  final Map<int, int> _timerCallbackRefs = {};
  int _nextId = 1;

  void bind(LuaState ls, LuaCallbackInvoker callbacks) {
    ls.newTable();

    // timer.setTimeout(ms, callback) -> timerId
    ls.pushDartFunction((ls) {
      final ms = ls.checkInteger(1) ?? 0;
      final cbRef = callbacks.ref(2);
      if (cbRef == null) {
        ls.error2('timer.setTimeout: 必须提供有效的回调函数');
        return 0;
      }

      final timerId = _nextId++;
      _timerCallbackRefs[timerId] = cbRef;
      _activeTimers[timerId] = Timer(Duration(milliseconds: ms), () {
        _activeTimers.remove(timerId);
        _timerCallbackRefs.remove(timerId);
        callbacks.invokeAndRelease(cbRef, []);
      });

      ls.pushInteger(timerId);
      return 1;
    });
    ls.setField(-2, 'setTimeout');

    // timer.setInterval(ms, callback) -> timerId
    ls.pushDartFunction((ls) {
      final ms = ls.checkInteger(1) ?? 0;
      final cbRef = callbacks.ref(2);
      if (cbRef == null) {
        ls.error2('timer.setInterval: 必须提供有效的回调函数');
        return 0;
      }

      final timerId = _nextId++;
      _timerCallbackRefs[timerId] = cbRef;
      _activeTimers[timerId] = Timer.periodic(Duration(milliseconds: ms), (t) {
        callbacks.invoke(cbRef, []);
      });

      ls.pushInteger(timerId);
      return 1;
    });
    ls.setField(-2, 'setInterval');

    // timer.clear(timerId)
    ls.pushDartFunction((ls) {
      final timerId = ls.checkInteger(1) ?? 0;
      clearTimer(timerId, callbacks);
      return 0;
    });
    ls.setField(-2, 'clear');

    // timer.clearAll()
    ls.pushDartFunction((ls) {
      clearAll(callbacks);
      return 0;
    });
    ls.setField(-2, 'clearAll');

    ls.setGlobal('timer');
  }

  void clearTimer(int timerId, LuaCallbackInvoker callbacks) {
    _activeTimers.remove(timerId)?.cancel();
    final cbRef = _timerCallbackRefs.remove(timerId);
    if (cbRef != null) {
      callbacks.release(cbRef);
    }
  }

  void clearAll(LuaCallbackInvoker callbacks) {
    for (final timer in _activeTimers.values) {
      timer.cancel();
    }
    _activeTimers.clear();
    for (final cbRef in _timerCallbackRefs.values) {
      callbacks.release(cbRef);
    }
    _timerCallbackRefs.clear();
  }

  void dispose(LuaCallbackInvoker? callbacks) {
    for (final timer in _activeTimers.values) {
      timer.cancel();
    }
    _activeTimers.clear();
    if (callbacks != null) {
      for (final cbRef in _timerCallbackRefs.values) {
        callbacks.release(cbRef);
      }
    }
    _timerCallbackRefs.clear();
  }
}
