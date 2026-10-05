import 'dart:io';
import 'package:flutter/widgets.dart';
import '../model/plugin_manifest.dart';
import '../model/plugin_category.dart';
import 'tool_plugin.dart';
import 'plugin_context.dart';

/// 动态加载的 .ptx 插件实体
class DynamicPlugin extends ToolPlugin {
  static const IconData defaultIcon = IconData(0xe247, fontFamily: 'MaterialIcons');

  final PluginManifest manifest;
  final Directory rootDir;
  PluginContext? _context;

  DynamicPlugin({
    required this.manifest,
    required this.rootDir,
  });

  @override
  bool get isDynamic => true;

  @override
  String get id => manifest.id;

  @override
  String get name => manifest.name;

  @override
  String get description => manifest.description;

  @override
  String get version => manifest.version;

  @override
  PluginCategory get category => manifest.category;

  @override
  IconData get icon => defaultIcon; // 动态插件通用图标，若有本地图标由 UI 渲染

  @override
  ImageProvider? get iconProvider {
    final file = iconFile;
    return file != null ? FileImage(file) : null;
  }

  File get entryScriptFile => File('${rootDir.path}/${manifest.entry}');
  File get uiDefinitionFile => File('${rootDir.path}/${manifest.ui}');
  File? get iconFile => manifest.icon != null ? File('${rootDir.path}/${manifest.icon}') : null;

  PluginContext? get context => _context;

  @override
  Future<void> initialize(PluginContext context) async {
    _context = context;
    context.logger.i('DynamicPlugin [$id] initialized.');
  }

  @override
  Future<void> dispose() async {
    _context?.logger.i('DynamicPlugin [$id] disposed.');
    _context = null;
  }
}
