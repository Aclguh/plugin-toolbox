import 'dart:io';

import 'package:archive/archive.dart';
import 'package:lua_dardo/lua.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';

/// `archive` — 压缩归档处理 API。
///
/// 严格受限于插件沙箱目录，具备完整的 Zip Slip 路径穿越防御，
/// 支持解压缩、目录打包以及压缩包内条目罗列。
class ArchiveApi {
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

    // archive.unzip(zipRelPath, targetDirRel) -> bool, error
    ls.pushDartFunction((ls) {
      checkStoragePermission(ls);
      final zipRel = ls.checkString(1) ?? '';
      final targetRel = ls.checkString(2) ?? '';

      final zipFull = resolveSafePath(ls, zipRel);
      final targetFull = resolveSafePath(ls, targetRel);

      final zipFile = File(zipFull);
      if (!zipFile.existsSync()) {
        ls.pushBoolean(false);
        ls.pushString('ZIP 文件不存在: $zipRel');
        return 2;
      }

      try {
        final bytes = zipFile.readAsBytesSync();
        final archive = ZipDecoder().decodeBytes(bytes);

        final targetDir = Directory(targetFull);
        if (!targetDir.existsSync()) {
          targetDir.createSync(recursive: true);
        }

        for (final entry in archive) {
          // 严格防范 Zip Slip 攻击
          if (!SandboxPath.isSafeRelativeEntry(entry.name)) {
            continue;
          }

          final outPath = '$targetFull/${entry.name}';
          if (entry.isFile) {
            final outFile = File(outPath);
            outFile.parent.createSync(recursive: true);
            outFile.writeAsBytesSync(entry.content as List<int>);
          } else {
            Directory(outPath).createSync(recursive: true);
          }
        }

        ls.pushBoolean(true);
        return 1;
      } catch (e) {
        ls.pushBoolean(false);
        ls.pushString(e.toString());
        return 2;
      }
    });
    ls.setField(-2, 'unzip');

    // archive.zip(sourceDirRel, zipRelPath) -> bool, error
    ls.pushDartFunction((ls) {
      checkStoragePermission(ls);
      final sourceRel = ls.checkString(1) ?? '';
      final zipRel = ls.checkString(2) ?? '';

      if (zipRel == 'plugin.json' || zipRel == 'manifest.json') {
        ls.error2('受保护的核心清单禁止覆写');
        return 0;
      }

      final sourceFull = resolveSafePath(ls, sourceRel);
      final zipFull = resolveSafePath(ls, zipRel);

      final sourceDir = Directory(sourceFull);
      if (!sourceDir.existsSync()) {
        ls.pushBoolean(false);
        ls.pushString('源目录不存在: $sourceRel');
        return 2;
      }

      try {
        final archive = Archive();
        final entities = sourceDir.listSync(recursive: true);

        for (final entity in entities) {
          if (entity is File) {
            final relName = entity.path
                .substring(sourceDir.path.length)
                .replaceAll(r'\', '/')
                .replaceFirst(RegExp(r'^/'), '');
            final bytes = entity.readAsBytesSync();
            archive.addFile(ArchiveFile(relName, bytes.length, bytes));
          }
        }

        final encoded = ZipEncoder().encode(archive);
        if (encoded == null) {
          ls.pushBoolean(false);
          ls.pushString('ZIP 编码失败');
          return 2;
        }

        final zipOut = File(zipFull);
        zipOut.parent.createSync(recursive: true);
        zipOut.writeAsBytesSync(encoded);

        ls.pushBoolean(true);
        return 1;
      } catch (e) {
        ls.pushBoolean(false);
        ls.pushString(e.toString());
        return 2;
      }
    });
    ls.setField(-2, 'zip');

    // archive.list(zipRelPath) -> table | nil, error
    ls.pushDartFunction((ls) {
      checkStoragePermission(ls);
      final zipRel = ls.checkString(1) ?? '';
      final zipFull = resolveSafePath(ls, zipRel);

      final zipFile = File(zipFull);
      if (!zipFile.existsSync()) {
        ls.pushNil();
        ls.pushString('ZIP 文件不存在: $zipRel');
        return 2;
      }

      try {
        final bytes = zipFile.readAsBytesSync();
        final archive = ZipDecoder().decodeBytes(bytes);

        ls.newTable();
        int idx = 1;
        for (final entry in archive) {
          ls.pushInteger(idx++);
          ls.newTable();

          ls.pushString('name');
          ls.pushString(entry.name);
          ls.setTable(-3);

          ls.pushString('size');
          ls.pushInteger(entry.size);
          ls.setTable(-3);

          ls.pushString('isFile');
          ls.pushBoolean(entry.isFile);
          ls.setTable(-3);

          ls.setTable(-3);
        }
        return 1;
      } catch (e) {
        ls.pushNil();
        ls.pushString(e.toString());
        return 2;
      }
    });
    ls.setField(-2, 'list');

    ls.setGlobal('archive');
  }
}
