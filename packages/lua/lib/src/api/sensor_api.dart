import 'dart:async';
import 'package:lua_dardo/lua.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';
import '../lua_callback_invoker.dart';
import '../lua_engine.dart';

/// `sensor` — 硬件传感器 API (加速度计 / 陀螺仪 / 磁力计 / 罗盘)。
class SensorApi {
  final Map<String, Timer> _pollingTimers = {};
  final Map<String, int> _callbackRefs = {};
  final Map<String, Map<String, dynamic>> _latestCache = {};
  bool _disposed = false;

  void bind(
    LuaState ls,
    PluginContext context,
    LuaHostDelegate delegate,
    LuaCallbackInvoker callbacks,
  ) {
    ls.newTable();

    void checkSensorPermission(LuaState ls) {
      if (!context.hasPermission(PluginPermission.sensor)) {
        ls.error2('权限不足: 插件未声明 sensor 权限');
      }
    }

    void pushMapAsTable(LuaState ls, Map<String, dynamic>? data) {
      if (data == null) {
        ls.pushNil();
        return;
      }
      ls.newTable();
      for (final entry in data.entries) {
        ls.pushString(entry.key);
        final val = entry.value;
        if (val is num) {
          ls.pushNumber(val.toDouble());
        } else if (val is bool) {
          ls.pushBoolean(val);
        } else if (val is String) {
          ls.pushString(val);
        } else {
          ls.pushString(val.toString());
        }
        ls.setTable(-3);
      }
    }

    // sensor.isAvailable(type) -> bool
    ls.pushDartFunction((ls) {
      checkSensorPermission(ls);
      final type = (ls.optString(1, 'accelerometer') ?? 'accelerometer').toLowerCase();
      final supported = ['accelerometer', 'gyroscope', 'magnetometer', 'compass'];
      ls.pushBoolean(supported.contains(type));
      return 1;
    });
    ls.setField(-2, 'isAvailable');

    // sensor.get(type) -> table | nil
    ls.pushDartFunction((ls) {
      checkSensorPermission(ls);
      final type = (ls.checkString(1) ?? '').toLowerCase();
      final data = _latestCache[type];
      pushMapAsTable(ls, data);
      return 1;
    });
    ls.setField(-2, 'get');

    // sensor.getAccelerometer() -> table | nil
    ls.pushDartFunction((ls) {
      checkSensorPermission(ls);
      final data = _latestCache['accelerometer'];
      pushMapAsTable(ls, data);
      return 1;
    });
    ls.setField(-2, 'getAccelerometer');

    // sensor.getGyroscope() -> table | nil
    ls.pushDartFunction((ls) {
      checkSensorPermission(ls);
      final data = _latestCache['gyroscope'];
      pushMapAsTable(ls, data);
      return 1;
    });
    ls.setField(-2, 'getGyroscope');

    // sensor.getCompass() -> table | nil
    ls.pushDartFunction((ls) {
      checkSensorPermission(ls);
      final data = _latestCache['compass'];
      pushMapAsTable(ls, data);
      return 1;
    });
    ls.setField(-2, 'getCompass');

    // sensor.start(type [, callback])
    ls.pushDartFunction((ls) {
      checkSensorPermission(ls);
      if (_disposed) return 0;
      final type = (ls.checkString(1) ?? '').toLowerCase();
      final cbRef = callbacks.ref(2);

      // 停止同类型的旧监听
      _stopInternal(type, delegate, callbacks);

      if (cbRef != null) {
        _callbackRefs[type] = cbRef;
      }

      unawaited(delegate.startSensor(type));

      // 启动周期轮询同步至 Lua 缓存与回调 (100ms 刷新率，UI 级流畅且功耗低)
      _pollingTimers[type] =
          Timer.periodic(const Duration(milliseconds: 100), (timer) {
        if (_disposed) {
          timer.cancel();
          return;
        }
        delegate.getSensorData(type).then((reading) {
          if (reading != null && !_disposed) {
            _latestCache[type] = reading;
            delegate.onStateChanged('__sensor_$type', reading);
            final ref = _callbackRefs[type];
            if (ref != null) {
              callbacks.invoke(ref, [reading]);
            }
          }
        }).catchError((Object _) {});
      });

      ls.pushBoolean(true);
      return 1;
    });
    ls.setField(-2, 'start');

    // sensor.stop([type])
    ls.pushDartFunction((ls) {
      checkSensorPermission(ls);
      final type = ls.optString(1, '')?.toLowerCase() ?? '';
      if (type.isEmpty || type == 'all') {
        final allTypes = List<String>.from(_pollingTimers.keys);
        for (final t in allTypes) {
          _stopInternal(t, delegate, callbacks);
        }
      } else {
        _stopInternal(type, delegate, callbacks);
      }
      ls.pushBoolean(true);
      return 1;
    });
    ls.setField(-2, 'stop');

    ls.setGlobal('sensor');
  }

  void _stopInternal(
    String type,
    LuaHostDelegate delegate,
    LuaCallbackInvoker callbacks,
  ) {
    _pollingTimers.remove(type)?.cancel();
    final ref = _callbackRefs.remove(type);
    if (ref != null) {
      callbacks.release(ref);
    }
    unawaited(delegate.stopSensor(type));
  }

  /// 释放所有传感器监听与回调引用
  void dispose(LuaHostDelegate delegate, LuaCallbackInvoker callbacks) {
    _disposed = true;
    for (final timer in _pollingTimers.values) {
      timer.cancel();
    }
    _pollingTimers.clear();
    for (final ref in _callbackRefs.values) {
      callbacks.release(ref);
    }
    _callbackRefs.clear();
    _latestCache.clear();
    unawaited(delegate.stopSensor('all'));
  }
}
