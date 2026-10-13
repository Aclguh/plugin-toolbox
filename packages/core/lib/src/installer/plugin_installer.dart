import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';
import '../model/plugin_manifest.dart';
import '../plugin/dynamic_plugin.dart';
import '../event/event_bus.dart';
import '../event/app_event.dart';
import '../sandbox/sandbox_path.dart';
import '../storage/plugin_storage.dart';

class PluginInstaller {
  static const int maxPackageSizeBytes = 10 * 1024 * 1024; // 10MB
  static const int maxUncompressedSizeBytes = 50 * 1024 * 1024; // 50MB
  static const int maxInflationRatio = 20; // 膨胀比上限
  static const int inflationCheckThresholdBytes =
      5 * 1024 * 1024; // 5MB 以上开始校验膨胀比
  static const int maxEntryCount = 1000; // 包内条目数上限，防止数万空条目拖垮文件系统
  static final RegExp _validIdPattern = RegExp(r'^[a-z0-9_]{3,50}$');

  /// 从给定的 .ptx 文件路径进行解析与安装
  static Future<DynamicPlugin> installFromPtx(
    File ptxFile, {
    Directory? baseDirectory,
  }) async {
    final length = await ptxFile.length();
    if (length > maxPackageSizeBytes) {
      throw const FormatException('插件安装包过大 (超过 10MB)');
    }

    // 压缩包本体受 10MB 上限约束，全量读入内存是可控的；真正不可控的是
    // 解压展开体积，因此下面的解压循环逐条处理、每条写盘后立即释放其
    // 解压缓冲，使内存峰值只取决于单条最大条目而非整包展开总量。
    final bytes = await ptxFile.readAsBytes();
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('安装包不是有效的 ZIP/PTX 格式');
    }

    // 条目数在解压前即可凭 ZIP 中央目录判定，属于最廉价的炸弹前置拦截
    if (archive.files.length > maxEntryCount) {
      throw const FormatException('安装包条目数超限 (超过 $maxEntryCount 个)，疑似恶意压缩包');
    }

    // 1. 查找并解析 plugin.json
    final manifestEntry = archive.findFile('plugin.json');
    if (manifestEntry == null) {
      throw const FormatException('安装包中未找到 plugin.json 清单文件');
    }

    final manifestJsonStr = utf8.decode(manifestEntry.content as List<int>);
    final manifest = PluginManifest.fromJsonString(manifestJsonStr);
    manifestEntry.clear();

    // 2. 校验 ID 合法性（先于目录拼接，ID 合法则目录名必然安全）
    if (!_validIdPattern.hasMatch(manifest.id)) {
      throw FormatException('插件 ID [${manifest.id}] 不合法，仅允许 3-50 位小写字母、数字及下划线');
    }

    // 3. 校验 entry 和 ui
    if (archive.findFile(manifest.entry) == null) {
      throw FormatException('插件缺少入口脚本文件: ${manifest.entry}');
    }
    if (archive.findFile(manifest.ui) == null) {
      throw FormatException('插件缺少 UI 描述文件: ${manifest.ui}');
    }

    // 4. 定位目标安装目录
    final Directory pluginsBaseDir;
    if (baseDirectory != null) {
      pluginsBaseDir = baseDirectory;
    } else {
      final appDocDir = await getApplicationDocumentsDirectory();
      pluginsBaseDir = Directory('${appDocDir.path}/plugins');
    }
    final targetDir = Directory('${pluginsBaseDir.path}/${manifest.id}');
    // 暂存/备份目录与目标目录同父级，保证 rename 在同分区内原子完成；
    // 以 `.` 前缀命名，加载器会跳过隐藏目录，崩溃残留不会被误当插件加载
    final stagingDir =
        Directory('${pluginsBaseDir.path}/.${manifest.id}.staging');
    final backupDir =
        Directory('${pluginsBaseDir.path}/.${manifest.id}.backup');

    // 清理上次安装崩溃可能残留的暂存/备份目录
    await _deleteIfExists(stagingDir);
    await _deleteIfExists(backupDir);
    await stagingDir.create(recursive: true);

    // 5. 流式逐条解压到暂存目录 (防范 Zip Slip 路径穿越与 Zip Bomb 膨胀攻击)。
    // 先解压到暂存目录而非直接覆盖目标目录：升级安装时若解压中途失败，
    // 旧版本插件目录始终完好，不会因"先删后解压"而丢插件。
    try {
      int totalExtractedBytes = 0;
      for (final file in archive) {
        final filename = file.name;
        // 防御 Zip Slip 路径穿越攻击：由生产沙箱校验器统一拦截
        // `..` 穿越、POSIX/Windows 绝对路径与 UNC 路径等所有逃逸向量。
        if (!SandboxPath.isSafeRelativeEntry(filename)) {
          throw FormatException('检测到非法的包内相对路径: $filename');
        }
        if (file.isFile) {
          // 前置校验：ZIP 中央目录携带的声明解压体积若已超限，直接拒绝，
          // 不为必然失败的条目浪费一次完整解压（经典 zip 炸弹声明值均属实）。
          // 声明值可能被伪造偏小，因此解压后仍按实际字节累计复核（见下）。
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
          // 本条写盘后立即释放解压缓冲，约束整包解压的内存峰值
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

    // 6. 原子替换：旧目录先改名备份 -> 暂存目录改名上位 -> 清理备份。
    // 任一步失败则回滚恢复旧目录，保证升级失败不丢已安装插件。
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

    return DynamicPlugin(
      manifest: manifest,
      rootDir: targetDir,
    );
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
    if (await targetDir.exists()) {
      await targetDir.delete(recursive: true);
    }
    try {
      await storageFactory.create(pluginId).clear();
    } catch (_) {
      // 容灾: 存储异常不阻断卸载主流程
    }
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
