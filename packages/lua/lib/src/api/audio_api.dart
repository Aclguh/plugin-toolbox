import 'dart:async';
import 'package:lua_dardo/lua.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';
import '../lua_callback_invoker.dart';
import '../lua_engine.dart';

/// `audio` — 音频播放与频率发生器 API (文件播放 / 停止 / 正弦波发生器)。
class AudioApi {
  static void bind(
    LuaState ls,
    PluginContext context,
    LuaHostDelegate delegate,
    LuaCallbackInvoker callbacks,
  ) {
    ls.newTable();

    // audio.play(relPath [, callback])
    ls.pushDartFunction((ls) {
      if (!context.hasPermission(PluginPermission.storage)) {
        ls.error2('权限不足: 插件未声明 storage 权限');
        return 0;
      }
      final relPath = ls.checkString(1) ?? '';
      final rootDir = context.rootDir;
      if (rootDir == null) {
        ls.error2('沙箱未挂载: 当前插件上下文缺少 rootDir');
        return 0;
      }
      if (!SandboxPath.isSafeSubpath(rootDir.path, relPath)) {
        ls.error2('非法路径: 禁止逃逸沙箱 ($relPath)');
        return 0;
      }
      final fullPath = '${rootDir.path}/$relPath';
      final cbRef = callbacks.ref(2);

      unawaited(
        delegate.playAudio(fullPath).then((ok) {
          if (cbRef != null) {
            callbacks.invokeAndRelease(cbRef, [ok]);
          } else {
            delegate.onStateChanged('__audio_playing', ok);
          }
        }).catchError((Object _) {
          if (cbRef != null) {
            callbacks.invokeAndRelease(cbRef, [false]);
          } else {
            delegate.onStateChanged('__audio_playing', false);
          }
        }),
      );
      return 0;
    });
    ls.setField(-2, 'play');

    // audio.stop([callback])
    ls.pushDartFunction((ls) {
      final cbRef = callbacks.ref(1);
      unawaited(
        delegate.stopAudio().then((ok) {
          if (cbRef != null) {
            callbacks.invokeAndRelease(cbRef, [ok]);
          } else {
            delegate.onStateChanged('__audio_playing', false);
          }
        }).catchError((Object _) {
          if (cbRef != null) {
            callbacks.invokeAndRelease(cbRef, [false]);
          }
        }),
      );
      return 0;
    });
    ls.setField(-2, 'stop');

    // audio.playTone(frequencyHz, durationMs [, callback])
    ls.pushDartFunction((ls) {
      final freq = (ls.checkNumber(1) ?? 440.0).clamp(1.0, 24000.0);
      final duration = (ls.checkInteger(2) ?? 200).clamp(1, 10000);
      final cbRef = callbacks.ref(3);

      unawaited(
        delegate.playTone(freq, duration).then((ok) {
          if (cbRef != null) {
            callbacks.invokeAndRelease(cbRef, [ok]);
          }
        }).catchError((Object _) {
          if (cbRef != null) {
            callbacks.invokeAndRelease(cbRef, [false]);
          }
        }),
      );
      return 0;
    });
    ls.setField(-2, 'playTone');

    // audio.startRecord(destRelPath [, callback]) -> 录音至沙箱指定路径
    ls.pushDartFunction((ls) {
      if (!context.hasPermission(PluginPermission.microphone)) {
        ls.error2('权限不足: 插件未声明 microphone 权限');
        return 0;
      }
      if (!context.hasPermission(PluginPermission.storage)) {
        ls.error2('权限不足: 插件未声明 storage 权限');
        return 0;
      }
      final relPath = ls.checkString(1) ?? '';
      final rootDir = context.rootDir;
      if (rootDir == null) {
        ls.error2('沙箱未挂载: 当前插件上下文缺少 rootDir');
        return 0;
      }
      if (!SandboxPath.isSafeSubpath(rootDir.path, relPath)) {
        ls.error2('非法路径: 禁止逃逸沙箱 ($relPath)');
        return 0;
      }
      final fullPath = '${rootDir.path}/$relPath';
      final cbRef = callbacks.ref(2);

      unawaited(
        delegate.startAudioRecording(fullPath).then((ok) {
          if (cbRef != null) {
            callbacks.invokeAndRelease(cbRef, [ok]);
          } else {
            delegate.onStateChanged('__audio_recording', ok);
          }
        }).catchError((Object _) {
          if (cbRef != null) {
            callbacks.invokeAndRelease(cbRef, [false]);
          } else {
            delegate.onStateChanged('__audio_recording', false);
          }
        }),
      );
      return 0;
    });
    ls.setField(-2, 'startRecord');

    // audio.stopRecord([callback]) -> 停止录音并返回录音信息
    ls.pushDartFunction((ls) {
      final cbRef = callbacks.ref(1);
      unawaited(
        delegate.stopAudioRecording().then((info) {
          if (cbRef != null) {
            callbacks.invokeAndRelease(cbRef, [info]);
          } else {
            delegate.onStateChanged('__audio_recording', false);
          }
        }).catchError((Object _) {
          if (cbRef != null) {
            callbacks.invokeAndRelease(cbRef, [null]);
          } else {
            delegate.onStateChanged('__audio_recording', false);
          }
        }),
      );
      return 0;
    });
    ls.setField(-2, 'stopRecord');

    // audio.getDecibel([callback]) -> 实时环境声音分贝值 (dB)
    ls.pushDartFunction((ls) {
      if (!context.hasPermission(PluginPermission.microphone)) {
        ls.error2('权限不足: 插件未声明 microphone 权限');
        return 0;
      }
      final cbRef = callbacks.ref(1);
      unawaited(
        delegate.getAudioDecibel().then((db) {
          if (cbRef != null) {
            callbacks.invokeAndRelease(cbRef, [db]);
          } else {
            delegate.onStateChanged('__audio_decibel', db);
          }
        }).catchError((Object _) {
          if (cbRef != null) {
            callbacks.invokeAndRelease(cbRef, [0.0]);
          } else {
            delegate.onStateChanged('__audio_decibel', 0.0);
          }
        }),
      );
      return 0;
    });
    ls.setField(-2, 'getDecibel');

    ls.setGlobal('audio');
  }
}
