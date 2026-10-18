import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:lua_dardo/lua.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';

import '../../lua_callback_invoker.dart';
import '../sandbox_utils.dart';

/// 沙箱文件系统二进制与 Base64 / Hex 编码读写处理器
class FsBinaryHandler {
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

    bool isProtected(String relPath) =>
        isProtectedSandboxFile(context, relPath);

    // fs.readHex(relPath [, offset, length]) -> string | nil, error
    ls.pushDartFunction((ls) {
      checkStoragePermission(ls);
      final relPath = ls.checkString(1) ?? '';
      final fullPath = resolveSafePath(ls, relPath);
      final file = File(fullPath);
      if (!file.existsSync()) {
        ls.pushNil();
        ls.pushString('文件不存在: $relPath');
        return 2;
      }
      try {
        final bytes = file.readAsBytesSync();
        final offset = ls.optInteger(2, 0) ?? 0;
        final length = ls.optInteger(3, bytes.length) ?? bytes.length;

        final start = offset.clamp(0, bytes.length);
        final end = (start + length).clamp(start, bytes.length);
        final subBytes = bytes.sublist(start, end);

        final sb = StringBuffer();
        for (final b in subBytes) {
          sb.write(b.toRadixString(16).padLeft(2, '0'));
        }
        ls.pushString(sb.toString());
        return 1;
      } catch (e) {
        ls.pushNil();
        ls.pushString(e.toString());
        return 2;
      }
    });
    ls.setField(-2, 'readHex');

    // fs.writeHex(relPath, hexStr [, append]) -> bool, error
    ls.pushDartFunction((ls) {
      checkStoragePermission(ls);
      final relPath = ls.checkString(1) ?? '';
      final hexStr = ls.checkString(2) ?? '';
      final append = !ls.isNoneOrNil(3) && ls.toBoolean(3);
      final fullPath = resolveSafePath(ls, relPath);

      if (isProtected(relPath)) {
        ls.error2('受保护的核心清单禁止覆写');
        return 0;
      }

      final cleanHex = hexStr.replaceAll(RegExp(r'\s+'), '');
      if (cleanHex.length % 2 != 0) {
        ls.pushBoolean(false);
        ls.pushString('十六进制长度必须为偶数');
        return 2;
      }

      final bytes = <int>[];
      for (int i = 0; i < cleanHex.length; i += 2) {
        final byte = int.tryParse(cleanHex.substring(i, i + 2), radix: 16);
        if (byte == null) {
          ls.pushBoolean(false);
          ls.pushString('包含非法十六进制字符: ${cleanHex.substring(i, i + 2)}');
          return 2;
        }
        bytes.add(byte);
      }

      if (!context.checkStorageQuota(bytes.length)) {
        ls.pushBoolean(false);
        ls.pushString('存储配额超限: 写入将超出插件沙箱配额 (${context.storageQuotaMb}MB)');
        return 2;
      }

      try {
        final file = File(fullPath);
        final oldSize = file.existsSync() ? file.lengthSync() : 0;
        file.parent.createSync(recursive: true);
        file.writeAsBytesSync(
          bytes,
          mode: append ? FileMode.append : FileMode.write,
          flush: true,
        );
        final newSize = file.lengthSync();
        context.updateUsedBytes(newSize - oldSize);
        ls.pushBoolean(true);
        return 1;
      } catch (e) {
        ls.pushBoolean(false);
        ls.pushString(e.toString());
        return 2;
      }
    });
    ls.setField(-2, 'writeHex');

    // fs.writeBase64(relPath, base64Content [, callback]) -> bool, error
    ls.pushDartFunction((ls) {
      checkStoragePermission(ls);
      final relPath = ls.checkString(1) ?? '';
      var b64 = ls.checkString(2) ?? '';
      final cbRef = ls.type(3) == LuaType.luaFunction ? callbacks.ref(3) : null;
      if (b64.startsWith('data:')) {
        final comma = b64.indexOf(',');
        if (comma >= 0) {
          b64 = b64.substring(comma + 1);
        }
      }
      final fullPath = resolveSafePath(ls, relPath);
      if (isProtected(relPath)) {
        if (cbRef != null) {
          callbacks.invokeAndRelease(cbRef, [false, '受保护的核心清单禁止覆写']);
          return 0;
        }
        ls.error2('受保护的核心清单禁止覆写');
        return 0;
      }
      try {
        final bytes = base64Decode(b64.replaceAll(RegExp(r'\s+'), ''));
        if (cbRef != null) {
          if (!context.reserveStorageQuota(bytes.length)) {
            callbacks.invokeAndRelease(cbRef, [false, '存储配额超限: 写入将超出插件沙箱配额']);
            return 0;
          }
          unawaited(() async {
            try {
              final file = File(fullPath);
              final oldSize = await file.exists() ? await file.length() : 0;
              await file.parent.create(recursive: true);
              await file.writeAsBytes(bytes, flush: true);
              final newSize = await file.length();
              context.commitStorageQuota(bytes.length,
                  actualDelta: newSize - oldSize);
              callbacks.invokeAndRelease(cbRef, [true, null]);
            } catch (e) {
              context.rollbackStorageQuota(bytes.length);
              callbacks.invokeAndRelease(cbRef, [false, e.toString()]);
            }
          }());
          return 0;
        }
        if (!context.checkStorageQuota(bytes.length)) {
          ls.pushBoolean(false);
          ls.pushString('存储配额超限: 写入将超出插件沙箱配额');
          return 2;
        }
        final file = File(fullPath);
        final oldSize = file.existsSync() ? file.lengthSync() : 0;
        file.parent.createSync(recursive: true);
        file.writeAsBytesSync(bytes, flush: true);
        final newSize = file.lengthSync();
        context.updateUsedBytes(newSize - oldSize);
        ls.pushBoolean(true);
        return 1;
      } catch (e) {
        if (cbRef != null) {
          callbacks.invokeAndRelease(cbRef, [false, e.toString()]);
          return 0;
        }
        ls.pushBoolean(false);
        ls.pushString(e.toString());
        return 2;
      }
    });
    ls.setField(-2, 'writeBase64');

    // fs.readBase64(relPath [, callback]) -> string | nil, error
    ls.pushDartFunction((ls) {
      checkStoragePermission(ls);
      final relPath = ls.checkString(1) ?? '';
      final fullPath = resolveSafePath(ls, relPath);
      final cbRef = ls.type(2) == LuaType.luaFunction ? callbacks.ref(2) : null;
      if (cbRef != null) {
        unawaited(() async {
          try {
            final file = File(fullPath);
            if (!await file.exists()) {
              callbacks.invokeAndRelease(cbRef, [null, '文件不存在: $relPath']);
              return;
            }
            final bytes = await file.readAsBytes();
            callbacks.invokeAndRelease(cbRef, [base64Encode(bytes), null]);
          } catch (e) {
            callbacks.invokeAndRelease(cbRef, [null, e.toString()]);
          }
        }());
        return 0;
      }
      final file = File(fullPath);
      if (!file.existsSync()) {
        ls.pushNil();
        ls.pushString('文件不存在: $relPath');
        return 2;
      }
      try {
        final bytes = file.readAsBytesSync();
        ls.pushString(base64Encode(bytes));
        return 1;
      } catch (e) {
        ls.pushNil();
        ls.pushString(e.toString());
        return 2;
      }
    });
    ls.setField(-2, 'readBase64');
  }
}
