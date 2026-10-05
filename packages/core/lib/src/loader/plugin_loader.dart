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

    final loadedList = <DynamicPlugin>[];
    final entities = pluginsBaseDir.listSync();

    for (final entity in entities) {
      if (entity is Directory) {
        final manifestFile = File('${entity.path}/plugin.json');
        if (await manifestFile.exists()) {
          try {
            final content = await manifestFile.readAsString();
            final manifest = PluginManifest.fromJson(
              json.decode(content) as Map<String, dynamic>,
            );
            loadedList.add(DynamicPlugin(
              manifest: manifest,
              rootDir: entity,
            ));
          } catch (e, st) {
            effectiveLogger.w(
              '跳过损坏的插件目录: ${entity.path}',
              error: e,
              stackTrace: st,
            );
          }
        }
      }
    }

    return loadedList;
  }
}
