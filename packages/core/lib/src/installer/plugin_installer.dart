import 'package:crypto/crypto.dart';
import '../config/toolbox_constants.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';
import '../model/plugin_manifest.dart';
import '../plugin/dynamic_plugin.dart';
import '../event/event_bus.dart';
import '../event/app_event.dart';
import '../sandbox/sandbox_path.dart';
import '../storage/plugin_storage.dart';

class PluginInstaller {
  static const int maxPackageSizeBytes = ToolboxConstants.maxPackageSizeBytes;
  static const int maxUncompressedSizeBytes =
      ToolboxConstants.maxUncompressedSizeBytes;
  static const int maxInflationRatio = ToolboxConstants.maxInflationRatio;
  static const int inflationCheckThresholdBytes =
      ToolboxConstants.inflationCheckThresholdBytes;
  static const int maxEntryCount = ToolboxConstants.maxEntryCount;
  static final RegExp _validIdPattern = RegExp(r'^[a-z0-9_]{3,50}$');

  /// 校验字节序列是否为预编译的 Lua 二进制字节码（以 \x1bLua 魔数开头）
  static bool isLuaBytecode(List<int> bytes) =>
      SandboxPath.isLuaBytecode(bytes);

  /// 从给定的 .ptx 文件路径进行解析与安装。
  ///
  /// CPU 密集型的 ZIP 解码、膨胀比计算与文件展开操作全流程在独立后台 Isolate
  /// 中执行，彻底杜绝主 UI 线程丢帧与卡顿；完成后回传清单与沙箱目录。
  static Future<DynamicPlugin> installFromPtx(
    File ptxFile, {
    Directory? baseDirectory,
    String? expectedSha256,
  }) async {
    final length = await ptxFile.length();
    if (length > maxPackageSizeBytes) {
      throw const FormatException('插件安装包过大 (超过 10MB)');
    }

    final String pluginsBasePath;
    if (baseDirectory != null) {
      pluginsBasePath = baseDirectory.path;
    } else {
      final appDocDir = await getApplicationDocumentsDirectory();
      pluginsBasePath = '${appDocDir.path}/plugins';
    }

    final ptxPath = ptxFile.path;
    final installData = await Isolate.run(() => _extractAndInstallInIsolate(
          ptxPath: ptxPath,
          pluginsBasePath: pluginsBasePath,
          length: length,
          expectedSha256: expectedSha256,
        ));

    final manifest = PluginManifest.fromJsonString(installData['manifest']!);
    final targetDir = Directory(installData['targetDir']!);

    return DynamicPlugin(
      manifest: manifest,
      rootDir: targetDir,
    );
  }

  static Future<Map<String, String>> _extractAndInstallInIsolate({
    required String ptxPath,
    required String pluginsBasePath,
    required int length,
    String? expectedSha256,
  }) async {
    final ptxFile = File(ptxPath);
    final bytes = await ptxFile.readAsBytes();
    if (expectedSha256 != null && expectedSha256.trim().isNotEmpty) {
      final expectedClean = expectedSha256.trim();
      final digest = sha256.convert(bytes);
      final hexDigest = digest.toString().toLowerCase();
      final base64Digest = base64.encode(digest.bytes);
      if (expectedClean.toLowerCase() != hexDigest &&
          expectedClean != base64Digest) {
        throw const FormatException('安装包 SHA-256 完整性哈希校验失败，疑似文件已损坏或被篡改');
      }
    }
    if (!SandboxPath.isZipArchive(bytes)) {
      throw const FormatException('安装包不是有效的 ZIP/PTX 格式 (缺少文件签名魔数)');
    }
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('安装包不是有效的 ZIP/PTX 格式');
    }

    if (archive.files.length > maxEntryCount) {
      throw const FormatException('安装包条目数超限 (超过 $maxEntryCount 个)，疑似恶意压缩包');
    }

    final manifestEntry = archive.findFile('plugin.json');
    if (manifestEntry == null) {
      throw const FormatException('安装包中未找到 plugin.json 清单文件');
    }

    final manifestJsonStr = utf8.decode(manifestEntry.content as List<int>);
    final manifest = PluginManifest.fromJsonString(manifestJsonStr);
    manifestEntry.clear();

    if (!_validIdPattern.hasMatch(manifest.id)) {
      throw FormatException('插件 ID [${manifest.id}] 不合法，仅允许 3-50 位小写字母、数字及下划线');
    }

    final entryFile = archive.findFile(manifest.entry);
    if (entryFile == null) {
      throw FormatException('插件缺少入口脚本文件: ${manifest.entry}');
    }
    final entryBytes = entryFile.content as List<int>;
    if (isLuaBytecode(entryBytes)) {
      throw const FormatException('安全策略拦截: 插件入口脚本禁止使用预编译 Lua 字节码，必须为源码文本');
    }
    if (archive.findFile(manifest.ui) == null) {
      throw FormatException('插件缺少 UI 描述文件: ${manifest.ui}');
    }

    final pluginsBaseDir = Directory(pluginsBasePath);
    final targetDir = Directory('${pluginsBaseDir.path}/${manifest.id}');
    final stagingDir =
        Directory('${pluginsBaseDir.path}/.${manifest.id}.staging');
    final backupDir =
        Directory('${pluginsBaseDir.path}/.${manifest.id}.backup');

    await _deleteIfExists(stagingDir);
    await _deleteIfExists(backupDir);
    await stagingDir.create(recursive: true);

    try {
      int totalExtractedBytes = 0;
      for (final file in archive) {
        final filename = file.name;
        if (!SandboxPath.isSafeRelativeEntry(filename)) {
          throw FormatException('检测到非法的包内相对路径: $filename');
        }
        if (SandboxPath.isSymbolicLinkEntry(file.isSymbolicLink, file.mode)) {
          throw FormatException(
              '安全策略拦截: 安装包禁止包含符号链接 (Symbolic Link): $filename');
        }
        if (file.isFile) {
          if (file.size > 0 &&
              totalExtractedBytes + file.size > maxUncompressedSizeBytes) {
            throw const FormatException('解压展开体积超限 (超过 50MB)，疑似恶意解压炸弹');
          }
          final data = file.content as List<int>;
          totalExtractedBytes += data.length;
          if (totalExtractedBytes > maxUncompressedSizeBytes) {
            throw const FormatException('解压展开体积超限 (超过 50MB)，疑似恶意解压炸弹');
          }
          if (length > 0 &&
              totalExtractedBytes > inflationCheckThresholdBytes &&
              (totalExtractedBytes / length) > maxInflationRatio) {
            throw const FormatException('解压膨胀比超过安全限制 (20倍)，疑似恶意解压炸弹');
          }
          final outFile = File('${stagingDir.path}/$filename');
          await outFile.parent.create(recursive: true);
          await outFile.writeAsBytes(data, flush: true);
          file.clear();
        } else {
          await Directory('${stagingDir.path}/$filename')
              .create(recursive: true);
        }
      }
    } catch (_) {
      await _deleteIfExists(stagingDir);
      rethrow;
    }

    final hadOldInstall = await targetDir.exists();
    try {
      if (hadOldInstall) {
        await targetDir.rename(backupDir.path);
      }
      try {
        await stagingDir.rename(targetDir.path);
      } catch (_) {
        if (hadOldInstall) {
          await _renameSilently(backupDir, targetDir);
        }
        rethrow;
      }
    } catch (_) {
      await _deleteIfExists(stagingDir);
      rethrow;
    }
    await _deleteIfExists(backupDir);

    return {
      'manifest': manifestJsonStr,
      'targetDir': targetDir.path,
    };
  }

  /// 尽力删除目录：清理动作失败不阻断主流程（残留会在下次安装时再清理）
  static Future<void> _deleteIfExists(Directory dir) async {
    try {
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } on FileSystemException {
      // 忽略清理失败
    }
  }

  /// 尽力重命名：回滚恢复旧目录时使用，失败由上层重新抛出的原始异常覆盖
  static Future<void> _renameSilently(Directory from, Directory to) async {
    try {
      await from.rename(to.path);
    } on FileSystemException {
      // 忽略回滚失败
    }
  }

  /// 卸载插件并同步清理其命名空间下的持久化存储
  static Future<void> uninstall(
    String pluginId, {
    Directory? baseDirectory,
    PluginStorageFactory storageFactory = const PluginStorageFactory(),
  }) async {
    final Directory pluginsBaseDir;
    if (baseDirectory != null) {
      pluginsBaseDir = baseDirectory;
    } else {
      final appDocDir = await getApplicationDocumentsDirectory();
      pluginsBaseDir = Directory('${appDocDir.path}/plugins');
    }
    final targetDir = Directory('${pluginsBaseDir.path}/$pluginId');
    try {
      await storageFactory.create(pluginId, rootDir: targetDir).clear();
      await PluginStorageFactory.evict(pluginId, rootDir: targetDir);
    } catch (_) {
      // 容灾: 存储异常不阻断卸载主流程
    }
    if (await targetDir.exists()) {
      for (var attempt = 0; attempt < 5; attempt++) {
        try {
          if (await targetDir.exists()) {
            await targetDir.delete(recursive: true);
          }
          break;
        } on FileSystemException {
          if (attempt == 4) rethrow;
          await Future<void>.delayed(const Duration(milliseconds: 30));
        }
      }
    }
  }

  /// 将已安装的插件目录打包导出为 .ptx 归档字节序列（ZIP 格式）。
  ///
  /// 在独立后台 Isolate 中进行压缩编码，不阻塞 UI 线程。
  /// 会自动排除插件沙箱内运行期持久化存储文件（如 `storage.json` 及临时备份文件）
  /// 以及隐藏文件，确保导出的安装包干净纯粹。
  static Future<List<int>> exportToBytes(Directory pluginDir) async {
    if (!await pluginDir.exists()) {
      throw FileSystemException('插件目录不存在', pluginDir.path);
    }
    final manifestFile = File('${pluginDir.path}/plugin.json');
    if (!await manifestFile.exists()) {
      throw const FormatException('插件目录缺少 plugin.json 清单文件');
    }

    final pluginPath = pluginDir.path;

    final bytes = await Isolate.run(() {
      final dir = Directory(pluginPath);
      final archive = Archive();
      final entities = dir.listSync(recursive: true);
      for (final entity in entities) {
        if (entity is! File) continue;
        final relPath = entity.path
            .substring(dir.path.length)
            .replaceAll(r'\', '/')
            .replaceFirst(RegExp(r'^/+'), '');
        if (_shouldExcludeFromExport(relPath)) continue;
        final content = entity.readAsBytesSync();
        archive.addFile(ArchiveFile(relPath, content.length, content));
      }
      final zipEncoder = ZipEncoder();
      final zipBytes = zipEncoder.encode(archive);
      if (zipBytes == null) {
        throw const FormatException('ZIP 压缩打包失败');
      }
      return zipBytes;
    });

    return bytes;
  }

  /// 将已安装的插件目录打包导出为指定 .ptx 归档文件。
  static Future<File> exportToPtx(
    Directory pluginDir,
    File destinationPtxFile,
  ) async {
    final bytes = await exportToBytes(pluginDir);
    await destinationPtxFile.parent.create(recursive: true);
    await destinationPtxFile.writeAsBytes(bytes, flush: true);
    return destinationPtxFile;
  }

  static bool _shouldExcludeFromExport(String relPath) {
    if (relPath.endsWith('.ptx')) return true;
    final parts = relPath.split('/');
    for (final part in parts) {
      if (part.startsWith('.')) return true;
    }
    final filename = parts.last;
    if (filename == 'storage.json' ||
        filename.endsWith('.bak') ||
        filename.endsWith('.tmp')) {
      return true;
    }
    return false;
  }

  /// 监听卸载请求事件并执行沙箱目录与持久化数据清理。
  ///
  /// 注册中心只通过事件总线发出卸载请求（保持自身无文件系统职责），
  /// 由宿主在组装层调用本方法建立"请求 -> 清理"的桥接。
  static StreamSubscription<PluginUninstallRequestedEvent>
      listenUninstallRequests(
    EventBus eventBus, {
    Directory? baseDirectory,
    PluginStorageFactory storageFactory = const PluginStorageFactory(),
  }) {
    return eventBus.on<PluginUninstallRequestedEvent>().listen((event) async {
      try {
        await uninstall(
          event.pluginId,
          baseDirectory: baseDirectory,
          storageFactory: storageFactory,
        );
      } on FileSystemException {
        // 沙箱目录可能已被外部移除，卸载流程不因此中断
      }
    });
  }
}
