import 'package:lua_dardo/lua.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';

import '../lua_callback_invoker.dart';
import '../lua_engine.dart';

/// `bluetooth` — 蓝牙低功耗 (Bluetooth LE) 宿主 API。
class BluetoothApi {
  static void bind(
    LuaState ls,
    PluginContext context,
    LuaHostDelegate delegate,
    LuaCallbackInvoker callbacks,
  ) {
    ls.newTable();

    void checkPermission(LuaState ls) {
      if (!context.hasPermission(PluginPermission.bluetooth)) {
        ls.error2('权限不足: 插件未声明 bluetooth 权限');
      }
    }

    // bluetooth.isAvailable([callback]) -> bool
    ls.pushDartFunction((ls) {
      checkPermission(ls);
      if (ls.type(1) == LuaType.luaFunction) {
        final cbRef = callbacks.ref(1);
        if (cbRef != null) {
          delegate.isBluetoothAvailable().then((available) {
            callbacks.invokeAndRelease(cbRef, [available]);
          });
        }
        return 0;
      }
      ls.pushBoolean(false);
      return 1;
    });
    ls.setField(-2, 'isAvailable');

    // bluetooth.startScan(callback) -> 发现设备时多次触发回调
    ls.pushDartFunction((ls) {
      checkPermission(ls);
      final cbRef = callbacks.ref(1);
      if (cbRef != null) {
        delegate.startBluetoothScan((device) {
          callbacks.invoke(cbRef, [
            {'ok': true, 'device': device}
          ]);
        }).then((started) {
          if (!started) {
            callbacks.invokeAndRelease(cbRef, [
              {'ok': false, 'error': '无法启动蓝牙扫描 (请确认蓝牙已开启并授予必要权限)'}
            ]);
          }
        });
      }
      return 0;
    });
    ls.setField(-2, 'startScan');

    // bluetooth.stopScan([callback])
    ls.pushDartFunction((ls) {
      checkPermission(ls);
      int? cbRef;
      if (ls.type(1) == LuaType.luaFunction) {
        cbRef = callbacks.ref(1);
      }
      delegate.stopBluetoothScan().then((stopped) {
        if (cbRef != null) {
          callbacks.invokeAndRelease(cbRef, [stopped]);
        }
      });
      return 0;
    });
    ls.setField(-2, 'stopScan');

    // bluetooth.connect(deviceId, callback)
    ls.pushDartFunction((ls) {
      checkPermission(ls);
      final deviceId = ls.checkString(1) ?? '';
      final cbRef = callbacks.ref(2);

      if (cbRef != null) {
        delegate.connectBluetooth(deviceId).then((connected) {
          callbacks.invokeAndRelease(cbRef, [
            {'ok': connected, if (!connected) 'error': '连接 BLE 设备失败'}
          ]);
        }).catchError((Object e) {
          callbacks.invokeAndRelease(cbRef, [
            {'ok': false, 'error': e.toString()}
          ]);
        });
      }
      return 0;
    });
    ls.setField(-2, 'connect');

    // bluetooth.disconnect(deviceId [, callback])
    ls.pushDartFunction((ls) {
      checkPermission(ls);
      final deviceId = ls.checkString(1) ?? '';
      int? cbRef;
      if (ls.type(2) == LuaType.luaFunction) {
        cbRef = callbacks.ref(2);
      }
      delegate.disconnectBluetooth(deviceId).then((disconnected) {
        if (cbRef != null) {
          callbacks.invokeAndRelease(cbRef, [disconnected]);
        }
      });
      return 0;
    });
    ls.setField(-2, 'disconnect');

    // bluetooth.read(deviceId, serviceUuid, charUuid, callback)
    ls.pushDartFunction((ls) {
      checkPermission(ls);
      final deviceId = ls.checkString(1) ?? '';
      final serviceUuid = ls.checkString(2) ?? '';
      final charUuid = ls.checkString(3) ?? '';
      final cbRef = callbacks.ref(4);

      if (cbRef != null) {
        delegate
            .readBluetoothCharacteristic(deviceId, serviceUuid, charUuid)
            .then((val) {
          callbacks.invokeAndRelease(cbRef, [
            {
              'ok': val != null,
              if (val != null) 'value': val else 'error': '读取特征值失败',
            }
          ]);
        }).catchError((Object e) {
          callbacks.invokeAndRelease(cbRef, [
            {'ok': false, 'error': e.toString()}
          ]);
        });
      }
      return 0;
    });
    ls.setField(-2, 'read');

    // bluetooth.write(deviceId, serviceUuid, charUuid, value, callback)
    ls.pushDartFunction((ls) {
      checkPermission(ls);
      final deviceId = ls.checkString(1) ?? '';
      final serviceUuid = ls.checkString(2) ?? '';
      final charUuid = ls.checkString(3) ?? '';
      final value = ls.checkString(4) ?? '';
      final cbRef = callbacks.ref(5);

      if (cbRef != null) {
        delegate
            .writeBluetoothCharacteristic(deviceId, serviceUuid, charUuid, value)
            .then((success) {
          callbacks.invokeAndRelease(cbRef, [
            {'ok': success, if (!success) 'error': '写入特征值失败'}
          ]);
        }).catchError((Object e) {
          callbacks.invokeAndRelease(cbRef, [
            {'ok': false, 'error': e.toString()}
          ]);
        });
      }
      return 0;
    });
    ls.setField(-2, 'write');

    ls.setGlobal('bluetooth');
  }
}
