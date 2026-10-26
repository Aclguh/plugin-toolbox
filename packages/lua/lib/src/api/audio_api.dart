import 'api_guard.dart';
import 'dart:async';
import 'package:lua_dardo/lua.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';
import '../lua_callback_invoker.dart';
import '../lua_engine.dart';
import 'sandbox_utils.dart';

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
      ApiGuard.checkPermission(
          ls, context, PluginPermission.storage, 'audio.play');
      final relPath = ls.checkString(1) ?? '';
      final fullPath = resolveSandboxPath(ls, context, relPath);
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
      ApiGuard.checkPermission(
          ls, context, PluginPermission.microphone, 'audio.startRecord');
      ApiGuard.checkPermission(
          ls, context, PluginPermission.storage, 'audio.startRecord');
      final relPath = ls.checkString(1) ?? '';
      final fullPath = resolveSandboxPath(ls, context, relPath);
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
      ApiGuard.checkPermission(
          ls, context, PluginPermission.microphone, 'audio.getDecibel');
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
