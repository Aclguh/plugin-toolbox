import 'dart:async';
import 'dart:io';

import 'package:lua_dardo/lua.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';

import '../../lua_callback_invoker.dart';
import '../sandbox_utils.dart';

/// 沙箱文件系统基础操作处理器 (读写、存在性、删除、遍历、元数据、复制与移动)
class FsBasicHandler {
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

    // fs.readFile(relPath [, callback]) -> string | nil, error
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
            final content = await file.readAsString();
            callbacks.invokeAndRelease(cbRef, [content, null]);
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

    // fs.readFileAsync(relPath, callback)
    ls.pushDartFunction((ls) {
      checkStoragePermission(ls);
      final relPath = ls.checkString(1) ?? '';
      final fullPath = resolveSafePath(ls, relPath);
      final cbRef = callbacks.ref(2);
      if (cbRef == null) {
        ls.error2('fs.readFileAsync 必须提供 callback 回调函数');
        return 0;
      }
      unawaited(() async {
        try {
          final file = File(fullPath);
          if (!await file.exists()) {
            callbacks.invokeAndRelease(cbRef, [null, '文件不存在: $relPath']);
            return;
          }
          final content = await file.readAsString();
          callbacks.invokeAndRelease(cbRef, [content, null]);
        } catch (e) {
          callbacks.invokeAndRelease(cbRef, [null, e.toString()]);
        }
      }());
      return 0;
    });
    ls.setField(-2, 'readFileAsync');

    // fs.writeFile(relPath, content [, append, callback]) -> bool
    ls.pushDartFunction((ls) {
      checkStoragePermission(ls);
      final relPath = ls.checkString(1) ?? '';
      final content = ls.checkString(2) ?? '';
      bool append = false;
      int? cbRef;
      if (ls.type(3) == LuaType.luaFunction) {
        cbRef = callbacks.ref(3);
      } else {
        if (!ls.isNoneOrNil(3)) append = ls.toBoolean(3);
        if (ls.type(4) == LuaType.luaFunction) {
          cbRef = callbacks.ref(4);
        }
      }
      final fullPath = resolveSafePath(ls, relPath);

      // 保护清单和元数据不被篡改
      if (isProtected(relPath)) {
        if (cbRef != null) {
          callbacks.invokeAndRelease(cbRef, [false, '受保护的核心清单禁止覆写']);
          return 0;
        }
        ls.error2('受保护的核心清单禁止覆写');
        return 0;
      }

      if (cbRef != null) {
        if (!context.reserveStorageQuota(content.length)) {
          callbacks.invokeAndRelease(cbRef,
              [false, '存储配额超限: 写入将超出插件沙箱配额 (${context.storageQuotaMb}MB)']);
          return 0;
        }
        final callbackRef = cbRef;
        unawaited(() async {
          try {
            final file = File(fullPath);
            final oldSize = await file.exists() ? await file.length() : 0;
            await file.parent.create(recursive: true);
            await file.writeAsString(
              content,
              mode: append ? FileMode.append : FileMode.write,
              flush: true,
            );
            final newSize = await file.length();
            context.commitStorageQuota(content.length,
                actualDelta: newSize - oldSize);
            callbacks.invokeAndRelease(callbackRef, [true, null]);
          } catch (e) {
            context.rollbackStorageQuota(content.length);
            callbacks.invokeAndRelease(callbackRef, [false, e.toString()]);
          }
        }());
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

    // fs.writeFileAsync(relPath, content [, append], callback)
    ls.pushDartFunction((ls) {
      checkStoragePermission(ls);
      final relPath = ls.checkString(1) ?? '';
      final content = ls.checkString(2) ?? '';
      bool append = false;
      int? cbRef;
      if (ls.type(3) == LuaType.luaFunction) {
        cbRef = callbacks.ref(3);
      } else {
        if (!ls.isNoneOrNil(3)) append = ls.toBoolean(3);
        if (ls.type(4) == LuaType.luaFunction) {
          cbRef = callbacks.ref(4);
        }
      }

      if (cbRef == null) {
        ls.error2('fs.writeFileAsync 必须提供 callback 回调函数');
        return 0;
      }

      final callbackRef = cbRef;
      if (isProtected(relPath)) {
        callbacks.invokeAndRelease(callbackRef, [false, '受保护的核心清单禁止覆写']);
        return 0;
      }

      if (!context.reserveStorageQuota(content.length)) {
        callbacks.invokeAndRelease(callbackRef,
            [false, '存储配额超限: 写入将超出插件沙箱配额 (${context.storageQuotaMb}MB)']);
        return 0;
      }

      final fullPath = resolveSafePath(ls, relPath);
      unawaited(() async {
        try {
          final file = File(fullPath);
          final oldSize = await file.exists() ? await file.length() : 0;
          await file.parent.create(recursive: true);
          await file.writeAsString(
            content,
            mode: append ? FileMode.append : FileMode.write,
            flush: true,
          );
          final newSize = await file.length();
          context.commitStorageQuota(content.length,
              actualDelta: newSize - oldSize);
          callbacks.invokeAndRelease(callbackRef, [true, null]);
        } catch (e) {
          context.rollbackStorageQuota(content.length);
          callbacks.invokeAndRelease(callbackRef, [false, e.toString()]);
        }
      }());
      return 0;
    });
    ls.setField(-2, 'writeFileAsync');

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
      if (isProtected(relPath) || relPath.isEmpty) {
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
        unawaited(context.scanUsedBytes());
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
      final fullDirPath =
          relDir.isEmpty ? rootDir.path : resolveSafePath(ls, relDir);

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

    // fs.copy(srcRel, destRel) -> bool, error
    ls.pushDartFunction((ls) {
      checkStoragePermission(ls);
      final srcRel = ls.checkString(1) ?? '';
      final destRel = ls.checkString(2) ?? '';

      if (isProtected(destRel)) {
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

      if (isProtected(srcRel)) {
        ls.error2('受保护的核心清单禁止移动');
        return 0;
      }
      if (isProtected(destRel)) {
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
  }
}
