import '../model/plugin_category.dart';
import 'plugin_context.dart';

/// 所有插件（内嵌与动态）的基类领域模型接口。
///
/// 领域模型保持纯净，不反向依赖 Flutter UI 库（IconData / ImageProvider 等）。
/// 相关的视觉表现由 UI 表现层通过扩展方法提供。
abstract class ToolPlugin {
  String get id;
  String get name;
  String get description;
  String get version;
  PluginCategory get category;

  /// 是否为动态安装的插件（.ptx）
  bool get isDynamic => false;

  /// 插件图标标识名称（纯文本描述，如 'build'、'calculate'）
  String get iconName => 'build';

  /// 可选的沙箱内本地图片图标文件路径
  String? get iconPath => null;

  /// 插件路由标识
  String get routePath => id;

  /// 启动与初始化生命周期
  Future<void> initialize(PluginContext context);

  /// 销毁生命周期
  Future<void> dispose();
}
