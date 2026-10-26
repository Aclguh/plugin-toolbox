import 'dart:convert';
import 'dart:io';
import 'package:logger/logger.dart';
import 'package:path_provider/path_provider.dart';
import '../model/plugin_manifest.dart';
import '../plugin/dynamic_plugin.dart';

/// 动态插件加载器：负责扫描并实例化沙箱中已安装的插件
class PluginLoader {
  static final Logger _defaultLogger = Logger(
    printer: PrettyPrinter(methodCount: 0, lineLength: 80),
  );

  /// 扫描本地插件目录，加载所有合法安装的动态插件。
  ///
  /// 可选指定 [baseDirectory]（用于测试或自定义存储位置）与 [logger]（用于日志注入）。
  /// 若目录不存在或为空则返回空列表；损坏的插件目录将被捕获并输出警告日志，避免阻断其他插件加载。
  static Future<List<DynamicPlugin>> loadAllInstalledPlugins({
    Directory? baseDirectory,
    Logger? logger,
  }) async {
    final effectiveLogger = logger ?? _defaultLogger;
    Directory pluginsBaseDir;
    if (baseDirectory != null) {
      pluginsBaseDir = baseDirectory;
    } else {
      final appDocDir = await getApplicationDocumentsDirectory();
      pluginsBaseDir = Directory('${appDocDir.path}/plugins');
    }

    if (!await pluginsBaseDir.exists()) {
      return [];
    }

    // 启动路径使用异步流式列举，避免插件较多时 listSync 阻塞主线程
    final entities = await pluginsBaseDir.list().toList();

    // 筛选合法的插件子目录（排除安装器暂存/备份的隐藏目录）
    final pluginDirs = entities.whereType<Directory>().where((d) {
      final dirName = d.path.split(RegExp(r'[\\/]')).last;
      return !dirName.startsWith('.');
    }).toList();

    // 并行异步并发读取与解析各个插件清单，提升冷启动并发性能
    final loadTasks = pluginDirs.map((dir) async {
      final manifestFile = File('${dir.path}/plugin.json');
      if (!await manifestFile.exists()) return null;
      try {
        final content = await manifestFile.readAsString();
        final manifest = PluginManifest.fromJson(
          json.decode(content) as Map<String, dynamic>,
        );
        return DynamicPlugin(
          manifest: manifest,
          rootDir: dir,
        );
      } catch (e, st) {
        effectiveLogger.w(
          '跳过损坏的插件目录: ${dir.path}',
          error: e,
          stackTrace: st,
        );
        return null;
      }
    });

    final results = await Future.wait(loadTasks);
    return results.whereType<DynamicPlugin>().toList();
  }
}
