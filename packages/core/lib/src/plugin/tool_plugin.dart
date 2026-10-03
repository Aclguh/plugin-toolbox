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

  /// 可选的图片图标源：动态插件可提供沙箱内图标文件，
  /// UI 层据此前缀渲染而无需对具体插件类型做硬检查（保持多态）。
  /// 返回 null 时 UI 层回退到 [icon] 矢量图标。
  ImageProvider? get iconProvider => null;

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
