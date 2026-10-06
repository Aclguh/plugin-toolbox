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

  /// 插件专属沙箱存储配额上限 (MB)，默认 50MB
  final int storageQuotaMb;

  /// 创建插件运行上下文
  const PluginContext({
    required this.pluginId,
    required this.storage,
    required this.eventBus,
    required this.logger,
    required this.grantedPermissions,
    this.rootDir,
    this.storageQuotaMb = 50,
  });

  /// 检查插件是否已被授予指定权限 [perm]
  bool hasPermission(PluginPermission perm) => grantedPermissions.contains(perm);

  /// 检查当前沙箱是否在容纳 [additionalBytes] 后依然处于存储配额限制内
  bool checkStorageQuota(int additionalBytes) {
    if (rootDir == null) return true;
    final maxBytes = storageQuotaMb * 1024 * 1024;
    int currentBytes = 0;
    try {
      if (rootDir!.existsSync()) {
        for (final entity in rootDir!.listSync(recursive: true, followLinks: false)) {
          if (entity is File) {
            currentBytes += entity.lengthSync();
          }
        }
      }
    } catch (_) {}
    return (currentBytes + additionalBytes) <= maxBytes;
  }
}
