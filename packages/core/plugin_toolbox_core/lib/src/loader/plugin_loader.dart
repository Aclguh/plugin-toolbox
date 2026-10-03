import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../model/plugin_manifest.dart';
import '../plugin/dynamic_plugin.dart';

class PluginLoader {
  /// 扫描本地插件目录，加载所有合法安装的动态插件
  static Future<List<DynamicPlugin>> loadAllInstalledPlugins() async {
    final appDocDir = await getApplicationDocumentsDirectory();
    final pluginsBaseDir = Directory('${appDocDir.path}/plugins');
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
            final manifest = PluginManifest.fromJson(json.decode(content) as Map<String, dynamic>);
            loadedList.add(DynamicPlugin(
              manifest: manifest,
              rootDir: entity,
            ));
          } catch (_) {
            // 忽略损坏的插件目录或记录错误
          }
        }
      }
    }

    return loadedList;
  }
}
