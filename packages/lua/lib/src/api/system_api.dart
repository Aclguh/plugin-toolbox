import 'dart:io';
import 'dart:ui' show Brightness, FlutterView, PlatformDispatcher, Size;

import 'package:lua_dardo/lua.dart';
import '../lua_engine.dart';

/// `system` — 设备与运行环境基础信息（只读，无隐私敏感权限门槛）。
///
/// 仅暴露非敏感的公开信息（系统版本 / CPU 核数 / 语言区域 / 屏幕尺寸等），
/// 支撑"设备信息查看"类插件；文件系统、传感器、通话等敏感能力不在此面。
class SystemApi {
  static void bind(
    LuaState ls, [
    LuaHostDelegate? delegate,
    dynamic callbacks,
  ]) {
    ls.newTable();

    // system.platform()
    ls.pushDartFunction((ls) {
      ls.pushString(Platform.operatingSystem);
      return 1;
    });
    ls.setField(-2, 'platform');

    // system.osVersion()
    ls.pushDartFunction((ls) {
      ls.pushString(Platform.operatingSystemVersion);
      return 1;
    });
    ls.setField(-2, 'osVersion');

    // system.hostname()
    // 部分设备在无网络环境下解析主机名会抛 IO/OSError，降级为空串而非中断脚本
    ls.pushDartFunction((ls) {
      String hostname;
      try {
        hostname = Platform.localHostname;
      } on IOException {
        hostname = '';
      } on OSError {
        hostname = '';
      }
      ls.pushString(hostname);
      return 1;
    });
    ls.setField(-2, 'hostname');

    // system.cores()
    ls.pushDartFunction((ls) {
      ls.pushInteger(Platform.numberOfProcessors);
      return 1;
    });
    ls.setField(-2, 'cores');

    // system.locale()
    ls.pushDartFunction((ls) {
      ls.pushString(PlatformDispatcher.instance.locale.toString());
      return 1;
    });
    ls.setField(-2, 'locale');

    // system.screenWidth() / system.screenHeight()
    // 物理像素尺寸；桌面/测试等无可用视图场景降级为 0
    ls.pushDartFunction((ls) {
      ls.pushInteger(_viewSize?.width.round() ?? 0);
      return 1;
    });
    ls.setField(-2, 'screenWidth');

    ls.pushDartFunction((ls) {
      ls.pushInteger(_viewSize?.height.round() ?? 0);
      return 1;
    });
    ls.setField(-2, 'screenHeight');

    // system.pixelRatio()
    ls.pushDartFunction((ls) {
      ls.pushNumber(_view?.devicePixelRatio ?? 0.0);
      return 1;
    });
    ls.setField(-2, 'pixelRatio');

    // system.brightness() -> 'dark' | 'light'
    ls.pushDartFunction((ls) {
      ls.pushString(
        PlatformDispatcher.instance.platformBrightness == Brightness.dark
            ? 'dark'
            : 'light',
      );
      return 1;
    });
    ls.setField(-2, 'brightness');

    // system.batteryLevel([callback]) -> int (0 ~ 100)
    ls.pushDartFunction((ls) {
      if (ls.type(1) == LuaType.luaFunction && callbacks != null) {
        final cbRef = callbacks.ref(1);
        if (delegate != null) {
          delegate.getBatteryLevel().then((lvl) {
            callbacks.invokeAndRelease(cbRef, [lvl]);
          }).catchError((Object _) {
            callbacks.invokeAndRelease(cbRef, [delegate.batteryLevel]);
          });
        } else {
          callbacks.invokeAndRelease(cbRef, [100]);
        }
        return 0;
      }
      ls.pushInteger(delegate?.batteryLevel ?? 100);
      return 1;
    });
    ls.setField(-2, 'batteryLevel');

    // system.isCharging([callback]) -> bool
    ls.pushDartFunction((ls) {
      if (ls.type(1) == LuaType.luaFunction && callbacks != null) {
        final cbRef = callbacks.ref(1);
        if (delegate != null) {
          delegate.checkIsCharging().then((charging) {
            callbacks.invokeAndRelease(cbRef, [charging]);
          }).catchError((Object _) {
            callbacks.invokeAndRelease(cbRef, [delegate.isCharging]);
          });
        } else {
          callbacks.invokeAndRelease(cbRef, [false]);
        }
        return 0;
      }
      ls.pushBoolean(delegate?.isCharging ?? false);
      return 1;
    });
    ls.setField(-2, 'isCharging');

    // system.networkType([callback]) -> 'wifi' | 'cellular' | 'none' | 'unknown'
    ls.pushDartFunction((ls) {
      if (ls.type(1) == LuaType.luaFunction && callbacks != null) {
        final cbRef = callbacks.ref(1);
        if (delegate != null) {
          delegate.fetchNetworkType().then((net) {
            callbacks.invokeAndRelease(cbRef, [net]);
          }).catchError((Object _) {
            callbacks.invokeAndRelease(cbRef, [delegate.networkType]);
          });
        } else {
          callbacks.invokeAndRelease(cbRef, ['unknown']);
        }
        return 0;
      }
      ls.pushString(delegate?.networkType ?? 'unknown');
      return 1;
    });
    ls.setField(-2, 'networkType');

    // system.openUrl(url)
    ls.pushDartFunction((ls) {
      final url = ls.checkString(1) ?? '';
      if (delegate != null) {
        delegate.openUrl(url);
      }
      return 0;
    });
    ls.setField(-2, 'openUrl');

    ls.setGlobal('system');
  }

  static FlutterView? get _view => PlatformDispatcher.instance.implicitView;

  static Size? get _viewSize {
    final view = _view;
    if (view == null) return null;
    final size = view.physicalSize;
    if (size.width <= 0 || size.height <= 0) return null;
    return size;
  }
}
