import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import '../model/plugin_category.dart';
import 'plugin_context.dart';

/// 所有插件（内嵌与动态）的基类接口
abstract class ToolPlugin {
  String get id;
  String get name;
  String get description;
  String get version;
  PluginCategory get category;
  
  /// 是否为动态安装的插件（.ptx）
  bool get isDynamic => false;

  /// 图标（原生 IconData 或自定义）
  IconData get icon;

  /// 插件路由标识
  String get routePath => id;

  /// 构建插件所注册的页面路由
  List<RouteBase> buildRoutes();

  /// 启动与初始化生命周期
  Future<void> initialize(PluginContext context);

  /// 销毁生命周期
  Future<void> dispose();

  /// 可选自定义设置项构建
  Widget? buildSettings(BuildContext context) => null;
}
