import 'dart:io';
import 'package:lua_dardo/lua.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';

/// `fs` — 沙箱文件系统 API。
///
/// 严格受限于插件独立沙箱目录（`app_data/plugins/<id>/`），
/// 所有路径操作经 [SandboxPath.isSafeSubpath] 校验，绝不发生路径穿越。
class FsApi {
  static void bind(LuaState ls, PluginContext context) {
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

      final file = File(fullPath);
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(
        content,
        mode: append ? FileMode.append : FileMode.write,
        flush: true,
      );
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
        file.deleteSync();
        ls.pushBoolean(true);
        return 1;
      }
      final dir = Directory(fullPath);
      if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
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

    ls.setGlobal('fs');
  }
}
