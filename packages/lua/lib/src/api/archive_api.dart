import 'api_guard.dart';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:lua_dardo/lua.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';

import 'sandbox_utils.dart';

/// `archive` — 压缩归档处理 API。
///
/// 严格受限于插件沙箱目录，具备完整的 Zip Slip 路径穿越防御，
/// 支持解压缩、目录打包以及压缩包内条目罗列。
class ArchiveApi {
  /// 单个 ZIP 允许的最大条目数，防止海量条目耗尽内存与 inode
  static const int maxArchiveEntries = 1000;

  /// 解压总大小相对压缩包体积的最大膨胀比；小于 [ratioCheckFloorBytes]
  /// 的小包不做膨胀比裁决，避免误伤高压缩比的正常小档案
  static const int maxExpansionRatio = 100;
  static const int ratioCheckFloorBytes = 1024 * 1024;

  static void bind(LuaState ls, PluginContext context) {
    ls.newTable();

    void checkStoragePermission(LuaState ls) {
      ApiGuard.checkPermission(
          ls, context, PluginPermission.storage, 'archive');
    }

    // archive.unzip(zipRelPath, targetDirRel) -> bool, error
    ls.pushDartFunction((ls) {
      checkStoragePermission(ls);
      final zipRel = ls.checkString(1) ?? '';
      final targetRel = ls.checkString(2) ?? '';

      final zipFull = resolveSandboxPath(ls, context, zipRel);
      final targetFull = resolveSandboxPath(ls, context, targetRel);

      final zipFile = File(zipFull);
      if (!zipFile.existsSync()) {
        ls.pushBoolean(false);
        ls.pushString('ZIP 文件不存在: $zipRel');
        return 2;
      }

      try {
        final bytes = zipFile.readAsBytesSync();
        final archive = ZipDecoder().decodeBytes(bytes);

        // 写入前全量预检：累计条目数、解压总大小与膨胀比，任一超限即整体
        // 拒绝且不落盘任何文件，防止 zip bomb 绕过沙箱配额或半截写入。
        final quotaBytes = context.storageQuotaMb * 1024 * 1024;
        final entries = <ArchiveFile>[];
        var totalSize = 0;
        for (final entry in archive) {
          // 严格防范 Zip Slip 攻击
          if (!SandboxPath.isSafeRelativeEntry(entry.name)) {
            continue;
          }
          // 禁止借解压覆写沙箱根部的受保护核心清单
          if (isProtectedSandboxFile(context, '$targetRel/${entry.name}')) {
            continue;
          }
          entries.add(entry);
          if (entries.length > maxArchiveEntries) {
            ls.pushBoolean(false);
            ls.pushString('ZIP 条目数超限 (>$maxArchiveEntries)');
            return 2;
          }
          if (entry.isFile) {
            totalSize += entry.size;
            if (totalSize > quotaBytes) {
              ls.pushBoolean(false);
              ls.pushString('解压总大小超出沙箱存储配额 (${context.storageQuotaMb}MB)');
              return 2;
            }
            if (totalSize > ratioCheckFloorBytes &&
                totalSize > bytes.length * maxExpansionRatio) {
              ls.pushBoolean(false);
              ls.pushString('解压膨胀比超限 (>$maxExpansionRatio:1)，疑似 zip bomb');
              return 2;
            }
          }
        }

        if (!context.checkStorageQuota(totalSize)) {
          ls.pushBoolean(false);
          ls.pushString('存储配额超限: 解压将超出插件沙箱配额 (${context.storageQuotaMb}MB)');
          return 2;
        }

        final targetDir = Directory(targetFull);
        if (!targetDir.existsSync()) {
          targetDir.createSync(recursive: true);
        }

        for (final entry in entries) {
          final outPath = '$targetFull/${entry.name}';
          if (entry.isFile) {
            final outFile = File(outPath);
            outFile.parent.createSync(recursive: true);
            outFile.writeAsBytesSync(entry.content as List<int>);
          } else {
            Directory(outPath).createSync(recursive: true);
          }
        }
        context.updateUsedBytes(totalSize);

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

      if (isProtectedSandboxFile(context, zipRel)) {
        ls.error2('受保护的核心清单禁止覆写');
        return 0;
      }

      final sourceFull = resolveSandboxPath(ls, context, sourceRel);
      final zipFull = resolveSandboxPath(ls, context, zipRel);

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
      final zipFull = resolveSandboxPath(ls, context, zipRel);

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
