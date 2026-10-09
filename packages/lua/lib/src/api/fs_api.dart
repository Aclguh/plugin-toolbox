import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:lua_dardo/lua.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';
import '../lua_callback_invoker.dart';
import '../lua_engine.dart';

/// `fs` — 沙箱文件系统 API。
///
/// 严格受限于插件独立沙箱目录（`app_data/plugins/<id>/`），
/// 所有路径操作经 [SandboxPath.isSafeSubpath] 校验，绝不发生路径穿越。
class FsApi {
  static void bind(
    LuaState ls,
    PluginContext context,
    LuaHostDelegate delegate,
    LuaCallbackInvoker callbacks,
  ) {
    ls.newTable();

    void checkStoragePermission(LuaState ls) {
      if (!context.hasPermission(PluginPermission.storage)) {
        ls.error2('权限不足: 插件未声明 storage 权限');
      }
    }

    String resolveSafePath(LuaState ls, String relPath) {
      final rootDir = context.rootDir;
      if (rootDir == null) {
        ls.error2('沙箱未挂载: 当前插件上下文缺少 rootDir');
        return '';
      }
      if (!SandboxPath.isSafeSubpath(rootDir.path, relPath)) {
        ls.error2('非法路径: 禁止逃逸沙箱 ($relPath)');
        return '';
      }
      return '${rootDir.path}/$relPath';
    }

    // fs.readFile(relPath) -> string | nil, error
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
        final content = file.readAsStringSync();
        ls.pushString(content);
        return 1;
      } catch (e) {
        ls.pushNil();
        ls.pushString(e.toString());
        return 2;
      }
    });
    ls.setField(-2, 'readFile');

    // fs.writeFile(relPath, content [, append]) -> bool
    ls.pushDartFunction((ls) {
      checkStoragePermission(ls);
      final relPath = ls.checkString(1) ?? '';
      final content = ls.checkString(2) ?? '';
      final append = !ls.isNoneOrNil(3) && ls.toBoolean(3);
      final fullPath = resolveSafePath(ls, relPath);

      // 保护清单和元数据不被篡改
      if (relPath == 'plugin.json' || relPath == 'manifest.json') {
        ls.error2('受保护的核心清单禁止覆写');
        return 0;
      }

      if (!context.checkStorageQuota(content.length)) {
        ls.error2('存储配额超限: 写入将超出插件沙箱配额 (${context.storageQuotaMb}MB)');
        return 0;
      }

      final file = File(fullPath);
      final oldSize = file.existsSync() ? file.lengthSync() : 0;
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(
        content,
        mode: append ? FileMode.append : FileMode.write,
        flush: true,
      );
      final newSize = file.lengthSync();
      context.updateUsedBytes(newSize - oldSize);
      ls.pushBoolean(true);
      return 1;
    });
    ls.setField(-2, 'writeFile');

    // fs.exists(relPath) -> bool
    ls.pushDartFunction((ls) {
      checkStoragePermission(ls);
      final relPath = ls.checkString(1) ?? '';
      final fullPath = resolveSafePath(ls, relPath);
      final exists =
          File(fullPath).existsSync() || Directory(fullPath).existsSync();
      ls.pushBoolean(exists);
      return 1;
    });
    ls.setField(-2, 'exists');

    // fs.remove(relPath) -> bool
    ls.pushDartFunction((ls) {
      checkStoragePermission(ls);
      final relPath = ls.checkString(1) ?? '';
      if (relPath == 'plugin.json' ||
          relPath == 'manifest.json' ||
          relPath.isEmpty) {
        ls.error2('受保护的核心资源禁止删除');
        return 0;
      }
      final fullPath = resolveSafePath(ls, relPath);
      final file = File(fullPath);
      if (file.existsSync()) {
        final len = file.lengthSync();
        file.deleteSync();
        context.updateUsedBytes(-len);
        ls.pushBoolean(true);
        return 1;
      }
      final dir = Directory(fullPath);
      if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
        context.invalidateStorageQuotaCache();
        ls.pushBoolean(true);
        return 1;
      }
      ls.pushBoolean(false);
      return 1;
    });
    ls.setField(-2, 'remove');

    // fs.listFiles([relDir]) -> table (list of relative names)
    ls.pushDartFunction((ls) {
      checkStoragePermission(ls);
      final rootDir = context.rootDir;
      if (rootDir == null) {
        ls.error2('沙箱未挂载: 当前插件上下文缺少 rootDir');
        return 0;
      }
      final relDir = ls.optString(1, '') ?? '';
      final fullDirPath = relDir.isEmpty
          ? rootDir.path
          : resolveSafePath(ls, relDir);

      final dir = Directory(fullDirPath);
      if (!dir.existsSync()) {
        ls.newTable();
        return 1;
      }

      final entities = dir.listSync();
      ls.newTable();
      int index = 1;
      for (final e in entities) {
        final name = e.uri.pathSegments.isNotEmpty
            ? e.uri.pathSegments[e.uri.pathSegments.length -
                (e.uri.pathSegments.last.isEmpty ? 2 : 1)]
            : e.path;
        ls.pushInteger(index++);
        ls.pushString(name);
        ls.setTable(-3);
      }
      return 1;
    });
    ls.setField(-2, 'listFiles');

    // fs.stat(relPath) -> table { size, modifiedMs, isDirectory } | nil
    ls.pushDartFunction((ls) {
      checkStoragePermission(ls);
      final relPath = ls.checkString(1) ?? '';
      final fullPath = resolveSafePath(ls, relPath);
      final f = File(fullPath);
      if (f.existsSync()) {
        final stat = f.statSync();
        ls.newTable();
        ls.pushString('size');
        ls.pushInteger(stat.size);
        ls.setTable(-3);

        ls.pushString('modifiedMs');
        ls.pushInteger(stat.modified.millisecondsSinceEpoch);
        ls.setTable(-3);

        ls.pushString('isDirectory');
        ls.pushBoolean(stat.type == FileSystemEntityType.directory);
        ls.setTable(-3);
        return 1;
      }

      final d = Directory(fullPath);
      if (d.existsSync()) {
        final stat = d.statSync();
        ls.newTable();
        ls.pushString('size');
        ls.pushInteger(stat.size);
        ls.setTable(-3);

        ls.pushString('modifiedMs');
        ls.pushInteger(stat.modified.millisecondsSinceEpoch);
        ls.setTable(-3);

        ls.pushString('isDirectory');
        ls.pushBoolean(true);
        ls.setTable(-3);
        return 1;
      }

      ls.pushNil();
      return 1;
    });
    ls.setField(-2, 'stat');

    // fs.fileSize(relPath) -> integer | nil, error
    ls.pushDartFunction((ls) {
      checkStoragePermission(ls);
      final relPath = ls.checkString(1) ?? '';
      final fullPath = resolveSafePath(ls, relPath);
      final f = File(fullPath);
      if (f.existsSync()) {
        ls.pushInteger(f.lengthSync());
        return 1;
      }
      ls.pushNil();
      ls.pushString('文件不存在: $relPath');
      return 2;
    });
    ls.setField(-2, 'fileSize');

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

      if (relPath == 'plugin.json' || relPath == 'manifest.json') {
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

    // fs.copy(srcRel, destRel) -> bool, error
    ls.pushDartFunction((ls) {
      checkStoragePermission(ls);
      final srcRel = ls.checkString(1) ?? '';
      final destRel = ls.checkString(2) ?? '';

      if (destRel == 'plugin.json' || destRel == 'manifest.json') {
        ls.error2('受保护的核心清单禁止覆写');
        return 0;
      }

      final srcFull = resolveSafePath(ls, srcRel);
      final destFull = resolveSafePath(ls, destRel);

      final srcFile = File(srcFull);
      if (!srcFile.existsSync()) {
        ls.pushBoolean(false);
        ls.pushString('源文件不存在: $srcRel');
        return 2;
      }

      if (!context.checkStorageQuota(srcFile.lengthSync())) {
        ls.pushBoolean(false);
        ls.pushString('存储配额超限: 复制将超出插件沙箱配额 (${context.storageQuotaMb}MB)');
        return 2;
      }

      try {
        final destFile = File(destFull);
        final oldSize = destFile.existsSync() ? destFile.lengthSync() : 0;
        destFile.parent.createSync(recursive: true);
        srcFile.copySync(destFull);
        final newSize = destFile.lengthSync();
        context.updateUsedBytes(newSize - oldSize);
        ls.pushBoolean(true);
        return 1;
      } catch (e) {
        ls.pushBoolean(false);
        ls.pushString(e.toString());
        return 2;
      }
    });
    ls.setField(-2, 'copy');

    // fs.move(srcRel, destRel) -> bool, error
    ls.pushDartFunction((ls) {
      checkStoragePermission(ls);
      final srcRel = ls.checkString(1) ?? '';
      final destRel = ls.checkString(2) ?? '';

      if (srcRel == 'plugin.json' || srcRel == 'manifest.json') {
        ls.error2('受保护的核心清单禁止移动');
        return 0;
      }
      if (destRel == 'plugin.json' || destRel == 'manifest.json') {
        ls.error2('受保护的核心清单禁止覆写');
        return 0;
      }

      final srcFull = resolveSafePath(ls, srcRel);
      final destFull = resolveSafePath(ls, destRel);

      final srcFile = File(srcFull);
      if (!srcFile.existsSync()) {
        ls.pushBoolean(false);
        ls.pushString('源文件不存在: $srcRel');
        return 2;
      }

      try {
        final destFile = File(destFull);
        destFile.parent.createSync(recursive: true);
        srcFile.renameSync(destFull);
        ls.pushBoolean(true);
        return 1;
      } catch (e) {
        ls.pushBoolean(false);
        ls.pushString(e.toString());
        return 2;
      }
    });
    ls.setField(-2, 'move');

    // fs.saveToGallery(relPath [, callback])
    ls.pushDartFunction((ls) {
      checkStoragePermission(ls);
      final relPath = ls.checkString(1) ?? '';
      final fullPath = resolveSafePath(ls, relPath);
      final file = File(fullPath);
      if (!file.existsSync()) {
        ls.error2('文件不存在: $relPath');
        return 0;
      }

      final lower = relPath.toLowerCase();
      final isImage = lower.endsWith('.png') ||
          lower.endsWith('.jpg') ||
          lower.endsWith('.jpeg') ||
          lower.endsWith('.webp') ||
          lower.endsWith('.gif') ||
          lower.endsWith('.bmp');
      if (!isImage) {
        ls.error2('类型不支持: 仅支持将图片文件保存至系统相册 ($relPath)');
        return 0;
      }

      final cbRef = callbacks.ref(2);
      unawaited(
        delegate.saveToGallery(fullPath).then((success) {
          if (cbRef != null) {
            callbacks.invokeAndRelease(cbRef, [success]);
          } else {
            delegate.onStateChanged('__fs_save_gallery', success);
          }
        }).catchError((Object err) {
          if (cbRef != null) {
            callbacks.invokeAndRelease(cbRef, [false, err.toString()]);
          } else {
            delegate.onStateChanged('__fs_save_gallery', false);
          }
        }),
      );
      return 0;
    });
    ls.setField(-2, 'saveToGallery');

    // fs.exportFile(relPath [, defaultName, callback])
    ls.pushDartFunction((ls) {
      checkStoragePermission(ls);
      final relPath = ls.checkString(1) ?? '';
      final fullPath = resolveSafePath(ls, relPath);
      final file = File(fullPath);
      if (!file.existsSync()) {
        ls.error2('文件不存在: $relPath');
        return 0;
      }

      String? defaultName;
      int? cbRef;

      if (ls.type(2) == LuaType.luaFunction) {
        cbRef = callbacks.ref(2);
      } else {
        if (!ls.isNoneOrNil(2)) defaultName = ls.toStr(2);
        if (ls.type(3) == LuaType.luaFunction) {
          cbRef = callbacks.ref(3);
        }
      }

      unawaited(
        delegate.exportFile(fullPath, defaultName: defaultName).then((success) {
          if (cbRef != null) {
            callbacks.invokeAndRelease(cbRef, [success]);
          } else {
            delegate.onStateChanged('__fs_export_file', success);
          }
        }).catchError((Object err) {
          if (cbRef != null) {
            callbacks.invokeAndRelease(cbRef, [false, err.toString()]);
          } else {
            delegate.onStateChanged('__fs_export_file', false);
          }
        }),
      );
      return 0;
    });
    ls.setField(-2, 'exportFile');

    // fs.pickFile([options, callback])
    // 选取外部文件并安全复制至插件沙箱 data/ 目录
    ls.pushDartFunction((ls) {
      checkStoragePermission(ls);
      List<String>? allowedExtensions;
      int? cbRef;

      if (ls.type(1) == LuaType.luaFunction) {
        cbRef = callbacks.ref(1);
      } else if (ls.type(1) == LuaType.luaTable) {
        ls.getField(1, 'allowedExtensions');
        if (ls.type(-1) == LuaType.luaTable) {
          final len = ls.rawLen(-1);
          final exts = <String>[];
          for (int i = 1; i <= len; i++) {
            ls.rawGetI(-1, i);
            if (ls.type(-1) == LuaType.luaString) {
              exts.add(ls.toStr(-1)!);
            }
            ls.pop(1);
          }
          if (exts.isNotEmpty) allowedExtensions = exts;
        }
        ls.pop(1);
        if (ls.type(2) == LuaType.luaFunction) {
          cbRef = callbacks.ref(2);
        }
      } else if (ls.type(1) == LuaType.luaString) {
        allowedExtensions = [ls.toStr(1)!];
        if (ls.type(2) == LuaType.luaFunction) {
          cbRef = callbacks.ref(2);
        }
      }

      unawaited(
        delegate.pickFile(allowedExtensions: allowedExtensions).then((relPath) {
          if (cbRef != null) {
            callbacks.invokeAndRelease(cbRef, [relPath]);
          } else if (relPath != null) {
            delegate.onStateChanged('__picked_file', relPath);
          }
        }).catchError((Object e) {
          if (cbRef != null) {
            callbacks.invokeAndRelease(cbRef, [null]);
          }
        }),
      );
      return 0;
    });
    ls.setField(-2, 'pickFile');

    // fs.writeBase64(relPath, base64Content) -> bool, error
    ls.pushDartFunction((ls) {
      checkStoragePermission(ls);
      final relPath = ls.checkString(1) ?? '';
      var b64 = ls.checkString(2) ?? '';
      if (b64.startsWith('data:')) {
        final comma = b64.indexOf(',');
        if (comma >= 0) {
          b64 = b64.substring(comma + 1);
        }
      }
      final fullPath = resolveSafePath(ls, relPath);
      if (relPath == 'plugin.json' || relPath == 'manifest.json') {
        ls.error2('受保护的核心清单禁止覆写');
        return 0;
      }
      try {
        final bytes = base64Decode(b64.replaceAll(RegExp(r'\s+'), ''));
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
        ls.pushBoolean(false);
        ls.pushString(e.toString());
        return 2;
      }
    });
    ls.setField(-2, 'writeBase64');

    // fs.readBase64(relPath) -> string | nil, error
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
        ls.pushString(base64Encode(bytes));
        return 1;
      } catch (e) {
        ls.pushNil();
        ls.pushString(e.toString());
        return 2;
      }
    });
    ls.setField(-2, 'readBase64');

    // fs.hash(relPath [, algo]) -> table | string | nil, error
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
        final algo = ls.type(2) == LuaType.luaString ? ls.toStr(2)?.toLowerCase() : null;
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

    ls.setGlobal('fs');
  }
}
