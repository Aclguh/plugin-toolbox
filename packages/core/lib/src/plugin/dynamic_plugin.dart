import 'dart:convert';
import 'dart:io';
import '../model/plugin_manifest.dart';
import '../model/plugin_category.dart';
import 'tool_plugin.dart';
import 'plugin_context.dart';

/// 动态加载的 .ptx 插件实体
class DynamicPlugin extends ToolPlugin {
  final PluginManifest manifest;
  final Directory rootDir;
  PluginContext? _context;
  Map<String, dynamic>? _cachedUiAst;

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
  String get iconName => 'build';

  @override
  String? get iconPath => iconFile?.path;

  File get entryScriptFile => File('${rootDir.path}/${manifest.entry}');
  File get uiDefinitionFile => File('${rootDir.path}/${manifest.ui}');
  File? get iconFile =>
      manifest.icon != null ? File('${rootDir.path}/${manifest.icon}') : null;

  PluginContext? get context => _context;

  /// 获取或读取并缓存 UI 声明式描述 AST，避免二次打开插件时重复执行磁盘 I/O 与 JSON 解析
  Future<Map<String, dynamic>> loadUiDefinition({bool reload = false}) async {
    if (!reload && _cachedUiAst != null) {
      return _cachedUiAst!;
    }
    final content = await uiDefinitionFile.readAsString();
    final decoded = json.decode(content);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('UI 描述文件必须是 JSON 对象');
    }
    _cachedUiAst = decoded;
    return _cachedUiAst!;
  }

  /// 清除 UI AST 内存缓存（插件更新或热重载时调用）
  void invalidateUiCache() {
    _cachedUiAst = null;
  }

  @override
  Future<void> initialize(PluginContext context) async {
    _context = context;
    context.logger.i('DynamicPlugin [$id] initialized.');
  }

  @override
  Future<void> dispose() async {
    _context = null;
    _cachedUiAst = null;
  }
}
