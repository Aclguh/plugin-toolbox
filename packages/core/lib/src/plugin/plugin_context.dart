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

  /// 插件允许访问的网络域名白名单（为 null 时不限制域名，非空时遵循 CSP 白名单规则）
  final List<String>? allowedDomains;

  /// 内存中缓存的沙箱已占用字节数（避免每次写入触发全量递归磁盘扫描）
  int? _cachedUsedBytes;

  /// 创建插件运行上下文
  PluginContext({
    required this.pluginId,
    required this.storage,
    required this.eventBus,
    required this.logger,
    required this.grantedPermissions,
    this.rootDir,
    this.storageQuotaMb = 50,
    this.allowedDomains,
  });

  /// 检查插件是否已被授予指定权限 [perm]
  bool hasPermission(PluginPermission perm) => grantedPermissions.contains(perm);

  /// 检查目标主机 [host] 是否在允许访问的域名白名单中
  bool isHostAllowed(String host) {
    if (allowedDomains == null || allowedDomains!.isEmpty) {
      return true; // 未配置白名单时默认放行（遵循已有 network 权限体系）
    }
    var normalized = host.trim().toLowerCase();
    // 去除端口号（兼容 host:port 与 [ipv6]:port）
    if (normalized.startsWith('[') && normalized.contains(']')) {
      normalized = normalized.substring(1, normalized.indexOf(']'));
    } else if (normalized.contains(':')) {
      normalized = normalized.split(':').first;
    }
    if (normalized.isEmpty) return false;

    for (final pattern in allowedDomains!) {
      final p = pattern.trim().toLowerCase();
      if (p.isEmpty) continue;
      if (p == '*' || p == normalized) return true;
      if (p.startsWith('*.')) {
        final suffix = p.substring(2);
        if (normalized == suffix || normalized.endsWith('.$suffix')) {
          return true;
        }
      } else if (normalized.endsWith('.$p')) {
        return true;
      }
    }
    return false;
  }

  /// 获取当前已使用的沙箱存储字节数
  int get currentUsedBytes {
    if (_cachedUsedBytes != null) return _cachedUsedBytes!;
    _cachedUsedBytes = _calculateDiskUsedBytes();
    return _cachedUsedBytes!;
  }

  int _calculateDiskUsedBytes() {
    if (rootDir == null) return 0;
    int bytes = 0;
    try {
      if (rootDir!.existsSync()) {
        for (final entity in rootDir!.listSync(recursive: true, followLinks: false)) {
          if (entity is File) {
            bytes += entity.lengthSync();
          }
        }
      }
    } catch (_) {}
    return bytes;
  }

  /// 检查当前沙箱是否在容纳 [additionalBytes] 后依然处于存储配额限制内
  bool checkStorageQuota(int additionalBytes) {
    if (rootDir == null) return true;
    final maxBytes = storageQuotaMb * 1024 * 1024;
    return (currentUsedBytes + additionalBytes) <= maxBytes;
  }

  /// 更新沙箱缓存字节增量（写入或删除文件时调用）
  void updateUsedBytes(int delta) {
    if (_cachedUsedBytes != null) {
      _cachedUsedBytes = (_cachedUsedBytes! + delta);
      if (_cachedUsedBytes! < 0) _cachedUsedBytes = 0;
    }
  }

  /// 清除缓存，下次检查时重新扫描全盘
  void invalidateStorageQuotaCache() {
    _cachedUsedBytes = null;
  }
}
