import 'dart:io';
import 'package:logger/logger.dart';
import '../event/event_bus.dart';
import '../storage/plugin_storage.dart';
import '../model/plugin_permission.dart';

/// 运行时注入给插件的上下文环境，封装了沙箱隔离的存储、事件总线、日志与授权信息
class PluginContext {
  /// 插件全局唯一标识符
  final String pluginId;

  /// 插件专属的命名空间隔离持久化存储
  final PluginStorage storage;

  /// 应用全局事件总线
  final EventBus eventBus;

  /// 专属于该插件的诊断日志输出器
  final Logger logger;

  /// 插件当前已获授权的权限集合
  final Set<PluginPermission> grantedPermissions;

  /// 插件专属沙箱根目录（用于动态插件沙箱文件系统隔离）
  final Directory? rootDir;

  /// 创建插件运行上下文
  const PluginContext({
    required this.pluginId,
    required this.storage,
    required this.eventBus,
    required this.logger,
    required this.grantedPermissions,
    this.rootDir,
  });

  /// 检查插件是否已被授予指定权限 [perm]
  bool hasPermission(PluginPermission perm) => grantedPermissions.contains(perm);
}
