import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:lua_dardo/lua.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';

import '../../lua_callback_invoker.dart';
import '../sandbox_utils.dart';

/// 沙箱文件系统哈希计算处理器 (MD5, SHA-1, SHA-256, CRC32 同步与 Isolate 异步计算)
class FsHashHandler {
  static Future<dynamic> computeHashInIsolate(
    String fullPath,
    String relPath,
    String? algo,
  ) async {
    return await Isolate.run(() async {
      final file = File(fullPath);
      final bytes = await file.readAsBytes();
      if (algo == 'md5') {
        return md5.convert(bytes).toString();
      } else if (algo == 'sha1') {
        return sha1.convert(bytes).toString();
      } else if (algo == 'sha256') {
        return sha256.convert(bytes).toString();
      } else if (algo == 'crc32') {
        final crc = getCrc32(bytes);
        return crc.toRadixString(16).padLeft(8, '0').toUpperCase();
      } else {
        final stat = file.statSync();
        final fileName = relPath.contains('/')
            ? relPath.substring(relPath.lastIndexOf('/') + 1)
            : relPath;
        final dotIdx = fileName.lastIndexOf('.');
        final ext = dotIdx >= 0 ? fileName.substring(dotIdx + 1) : '';
        final crc = getCrc32(bytes);
        return <String, dynamic>{
          'name': fileName,
          'size': bytes.length,
          'extension': ext,
          'modifiedMs': stat.modified.millisecondsSinceEpoch,
          'md5': md5.convert(bytes).toString(),
          'sha1': sha1.convert(bytes).toString(),
          'sha256': sha256.convert(bytes).toString(),
          'crc32': crc.toRadixString(16).padLeft(8, '0').toUpperCase(),
        };
      }
    });
  }

  static void register(
    LuaState ls,
    PluginContext context,
    LuaCallbackInvoker callbacks,
  ) {
    void checkStoragePermission(LuaState ls) {
      if (!context.hasPermission(PluginPermission.storage)) {
        ls.error2('权限不足: 插件未声明 storage 权限');
      }
    }

    String resolveSafePath(LuaState ls, String relPath) =>
        resolveSandboxPath(ls, context, relPath);

    // fs.hash(relPath [, algo] [, callback]) -> table | string | nil, error
    ls.pushDartFunction((ls) {
      checkStoragePermission(ls);
      final relPath = ls.checkString(1) ?? '';
      final fullPath = resolveSafePath(ls, relPath);
      final file = File(fullPath);

      String? algo;
      int? cbRef;
      if (ls.type(2) == LuaType.luaFunction) {
        cbRef = callbacks.ref(2);
      } else if (ls.type(2) == LuaType.luaString) {
        algo = ls.toStr(2)?.toLowerCase();
        if (ls.type(3) == LuaType.luaFunction) {
          cbRef = callbacks.ref(3);
        }
      }

      if (cbRef != null) {
        final callbackRef = cbRef;
        if (!file.existsSync()) {
          callbacks.invokeAndRelease(callbackRef, [null, '文件不存在: $relPath']);
          return 0;
        }
        unawaited(() async {
          try {
            final res = await computeHashInIsolate(fullPath, relPath, algo);
            callbacks.invokeAndRelease(callbackRef, [res, null]);
          } catch (e) {
            callbacks.invokeAndRelease(callbackRef, [null, e.toString()]);
          }
        }());
        return 0;
      }

      if (!file.existsSync()) {
        ls.pushNil();
        ls.pushString('文件不存在: $relPath');
        return 2;
      }
      try {
        final bytes = file.readAsBytesSync();
        if (algo == 'md5') {
          ls.pushString(md5.convert(bytes).toString());
          return 1;
        } else if (algo == 'sha1') {
          ls.pushString(sha1.convert(bytes).toString());
          return 1;
        } else if (algo == 'sha256') {
          ls.pushString(sha256.convert(bytes).toString());
          return 1;
        } else if (algo == 'crc32') {
          final crc = getCrc32(bytes);
          ls.pushString(crc.toRadixString(16).padLeft(8, '0').toUpperCase());
          return 1;
        } else {
          final stat = file.statSync();
          final fileName = relPath.contains('/')
              ? relPath.substring(relPath.lastIndexOf('/') + 1)
              : relPath;
          final dotIdx = fileName.lastIndexOf('.');
          final ext = dotIdx >= 0 ? fileName.substring(dotIdx + 1) : '';

          ls.newTable();
          ls.pushString('name');
          ls.pushString(fileName);
          ls.setTable(-3);

          ls.pushString('size');
          ls.pushInteger(bytes.length);
          ls.setTable(-3);

          ls.pushString('extension');
          ls.pushString(ext);
          ls.setTable(-3);

          ls.pushString('modifiedMs');
          ls.pushInteger(stat.modified.millisecondsSinceEpoch);
          ls.setTable(-3);

          ls.pushString('md5');
          ls.pushString(md5.convert(bytes).toString());
          ls.setTable(-3);

          ls.pushString('sha1');
          ls.pushString(sha1.convert(bytes).toString());
          ls.setTable(-3);

          ls.pushString('sha256');
          ls.pushString(sha256.convert(bytes).toString());
          ls.setTable(-3);

          final crc = getCrc32(bytes);
          ls.pushString('crc32');
          ls.pushString(crc.toRadixString(16).padLeft(8, '0').toUpperCase());
          ls.setTable(-3);

          return 1;
        }
      } catch (e) {
        ls.pushNil();
        ls.pushString(e.toString());
        return 2;
      }
    });
    ls.setField(-2, 'hash');

    // fs.hashAsync(relPath [, algo], callback)
    ls.pushDartFunction((ls) {
      checkStoragePermission(ls);
      final relPath = ls.checkString(1) ?? '';
      final fullPath = resolveSafePath(ls, relPath);
      String? algo;
      int? cbRef;
      if (ls.type(2) == LuaType.luaFunction) {
        cbRef = callbacks.ref(2);
      } else if (ls.type(2) == LuaType.luaString) {
        algo = ls.toStr(2)?.toLowerCase();
        if (ls.type(3) == LuaType.luaFunction) {
          cbRef = callbacks.ref(3);
        }
      }
      if (cbRef == null) {
        ls.error2('fs.hashAsync 必须提供 callback 回调函数');
        return 0;
      }
      final callbackRef = cbRef;
      final file = File(fullPath);
      if (!file.existsSync()) {
        callbacks.invokeAndRelease(callbackRef, [null, '文件不存在: $relPath']);
        return 0;
      }
      unawaited(() async {
        try {
          final res = await computeHashInIsolate(fullPath, relPath, algo);
          callbacks.invokeAndRelease(callbackRef, [res, null]);
        } catch (e) {
          callbacks.invokeAndRelease(callbackRef, [null, e.toString()]);
        }
      }());
      return 0;
    });
    ls.setField(-2, 'hashAsync');
  }
}
