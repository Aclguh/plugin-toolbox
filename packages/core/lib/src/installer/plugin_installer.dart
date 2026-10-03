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

class PluginInstaller {
  static const int maxPackageSizeBytes = 10 * 1024 * 1024; // 10MB
  static final RegExp _validIdPattern = RegExp(r'^[a-z0-9_]{3,50}$');

  /// 从给定的 .ptx 文件路径进行解析与安装
  static Future<DynamicPlugin> installFromPtx(File ptxFile) async {
    final length = await ptxFile.length();
    if (length > maxPackageSizeBytes) {
      throw const FormatException('插件安装包过大 (超过 10MB)');
    }

    final bytes = await ptxFile.readAsBytes();
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('安装包不是有效的 ZIP/PTX 格式');
    }

    // 1. 查找并解析 plugin.json
    final manifestEntry = archive.findFile('plugin.json');
    if (manifestEntry == null) {
      throw const FormatException('安装包中未找到 plugin.json 清单文件');
    }

    final manifestJsonStr = utf8.decode(manifestEntry.content as List<int>);
    final manifest = PluginManifest.fromJsonString(manifestJsonStr);

    // 2. 校验 ID 合法性
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
    final appDocDir = await getApplicationDocumentsDirectory();
    final targetDir = Directory('${appDocDir.path}/plugins/${manifest.id}');
    if (await targetDir.exists()) {
      await targetDir.delete(recursive: true);
    }
    await targetDir.create(recursive: true);

    // 5. 解压所有文件到沙箱目录
    for (final file in archive) {
      final filename = file.name;
      // 防御 Zip Slip 路径穿越攻击：由生产沙箱校验器统一拦截
      // `..` 穿越、POSIX/Windows 绝对路径与 UNC 路径等所有逃逸向量。
      if (!SandboxPath.isSafeRelativeEntry(filename)) {
        throw FormatException('检测到非法的包内相对路径: $filename');
      }
      if (file.isFile) {
        final data = file.content as List<int>;
        final outFile = File('${targetDir.path}/$filename');
        await outFile.parent.create(recursive: true);
        await outFile.writeAsBytes(data);
      } else {
        await Directory('${targetDir.path}/$filename').create(recursive: true);
      }
    }

    return DynamicPlugin(
      manifest: manifest,
      rootDir: targetDir,
    );
  }

  /// 卸载插件
  static Future<void> uninstall(String pluginId) async {
    final appDocDir = await getApplicationDocumentsDirectory();
    final targetDir = Directory('${appDocDir.path}/plugins/$pluginId');
    if (await targetDir.exists()) {
      await targetDir.delete(recursive: true);
    }
  }

  /// 监听卸载请求事件并执行沙箱目录清理。
  ///
  /// 注册中心只通过事件总线发出卸载请求（保持自身无文件系统职责），
  /// 由宿主在组装层调用本方法建立"请求 -> 清理"的桥接。
  static StreamSubscription<PluginUninstallRequestedEvent>
      listenUninstallRequests(EventBus eventBus) {
    return eventBus.on<PluginUninstallRequestedEvent>().listen((event) async {
      try {
        await uninstall(event.pluginId);
      } on FileSystemException {
        // 沙箱目录可能已被外部移除，卸载流程不因此中断
      }
    });
  }
}
