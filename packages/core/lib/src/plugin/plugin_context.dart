import 'dart:io';
import 'package:logger/logger.dart';
import '../event/event_bus.dart';
import '../storage/plugin_storage.dart';
import '../model/plugin_permission.dart';

/// 敏感权限调用运行时安全审计事件实体
class PermissionAuditRecord {
  final DateTime timestamp;
  final PluginPermission permission;
  final String action;
  final bool granted;
  final String? detail;

  const PermissionAuditRecord({
    required this.timestamp,
    required this.permission,
    required this.action,
    this.granted = true,
    this.detail,
  });

  @override
  String toString() {
    final time = timestamp.toIso8601String().substring(11, 19);
    final status = granted ? 'ALLOW' : 'DENY';
    final extra = detail != null && detail!.isNotEmpty ? ' ($detail)' : '';
    return '[$time] [$status] [${permission.name}] $action$extra';
  }
}

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

  /// 可选的沙箱磁盘体积扫描器（用于注入测试或外部自定义文件系统）
  final Future<int> Function(Directory dir)? diskScanner;

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
    this.diskScanner,
  });

  /// 检查插件是否已被授予指定权限 [perm]，并可选择性记录运行时审计轨迹
  bool hasPermission(PluginPermission perm,
      {String? auditAction, String? detail}) {
    final granted = grantedPermissions.contains(perm);
    if (auditAction != null) {
      recordAuditTrail(perm, auditAction, granted: granted, detail: detail);
    }
    return granted;
  }

  /// 动态更新插件已被授予的权限集合
  void setGrantedPermissions(Set<PluginPermission> permissions) {
    grantedPermissions
      ..clear()
      ..addAll(permissions);
  }

  /// 动态为插件授予单个权限
  void grantPermission(PluginPermission perm) {
    grantedPermissions.add(perm);
  }

  /// 动态撤销插件的单个权限
  void revokePermission(PluginPermission perm) {
    grantedPermissions.remove(perm);
  }

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

  /// 同步兜底扫描：Lua 宿主绑定层（fs_api）以同步链路调用
  /// [checkStorageQuota]，无法 await，因此同步读路径必须保留一个
  /// 同步实现作为兜底。具备异步上下文的调用方应优先使用
  /// [scanUsedBytes] 预热/刷新缓存，避免主线程同步磁盘 IO。
  int _calculateDiskUsedBytes() {
    if (rootDir == null) return 0;
    int bytes = 0;
    try {
      if (rootDir!.existsSync()) {
        for (final entity
            in rootDir!.listSync(recursive: true, followLinks: false)) {
          if (entity is File) {
            bytes += entity.lengthSync();
          }
        }
      }
    } catch (_) {}
    return bytes;
  }

  /// 异步递归扫描沙箱已占用字节数并刷新内存缓存。
  ///
  /// 调用后可安全地经 [currentUsedBytes] / [checkStorageQuota] 读取结果。
  Future<int> scanUsedBytes() async {
    final dir = rootDir;
    if (dir == null) {
      _cachedUsedBytes = 0;
      return 0;
    }
    if (diskScanner != null) {
      final bytes = await diskScanner!(dir);
      _cachedUsedBytes = bytes;
      return bytes;
    }
    _cachedUsedBytes = _calculateDiskUsedBytes();
    return _cachedUsedBytes!;
  }

  /// 内存中已预扣除但尚未落盘确认的字节数（防范异步并发写入引发的 TOCTOU 配额竞态）
  int _reservedBytes = 0;

  /// 获取当前已预扣但尚未实际落盘提交的字节数
  int get reservedBytes => _reservedBytes;

  /// 检查当前沙箱是否在容纳 [additionalBytes] 后依然处于存储配额限制内（含已预扣字节）
  bool checkStorageQuota(int additionalBytes) {
    if (rootDir == null) return true;
    final maxBytes = storageQuotaMb * 1024 * 1024;
    return (currentUsedBytes + _reservedBytes + additionalBytes) <= maxBytes;
  }

  /// 原子性预扣除沙箱存储配额（用于异步并发写入或下载前防范 TOCTOU 竞态突破上限）。
  /// 若预扣除后超出总配额，则返回 false 且不改变预扣状态。
  bool reserveStorageQuota(int bytes) {
    if (rootDir == null) return true;
    if (bytes <= 0) return true;
    final maxBytes = storageQuotaMb * 1024 * 1024;
    if ((currentUsedBytes + _reservedBytes + bytes) > maxBytes) {
      return false;
    }
    _reservedBytes += bytes;
    return true;
  }

  /// 提交并实际确认已预扣的存储配额（写入落盘成功时调用）。
  /// [reservedBytes] 为最初预扣的字节数，[actualDelta] 为实际产生的存储增量（若未提供则默认等于 reservedBytes）。
  void commitStorageQuota(int reservedBytes, {int? actualDelta}) {
    if (reservedBytes > 0) {
      _reservedBytes -= reservedBytes;
      if (_reservedBytes < 0) _reservedBytes = 0;
    }
    final delta = actualDelta ?? reservedBytes;
    updateUsedBytes(delta);
  }

  /// 回滚撤销已预扣的存储配额（写入取消或发生异常时调用）
  void rollbackStorageQuota(int reservedBytes) {
    if (reservedBytes > 0) {
      _reservedBytes -= reservedBytes;
      if (_reservedBytes < 0) _reservedBytes = 0;
    }
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
    _reservedBytes = 0;
  }

  /// 诊断控制台内存日志条目队列（最多保留 200 条，用于运行期诊断面板）
  final List<String> _diagnosticLogs = [];

  /// 获取不可变诊断日志视图
  List<String> get diagnosticLogs => List.unmodifiable(_diagnosticLogs);

  /// 记录一条诊断日志
  void recordLog(String message) {
    if (_diagnosticLogs.length >= 200) {
      _diagnosticLogs.removeAt(0);
    }
    final time = DateTime.now().toIso8601String().substring(11, 19);
    _diagnosticLogs.add('[$time] $message');
  }

  /// 清空诊断日志
  void clearDiagnosticLogs() {
    _diagnosticLogs.clear();
  }

  /// 权限审计轨迹队列（最多保留 100 条）
  final List<PermissionAuditRecord> _auditTrail = [];

  /// 获取不可变权限审计轨迹视图
  List<PermissionAuditRecord> get auditTrail => List.unmodifiable(_auditTrail);

  /// 记录一条权限审计轨迹
  void recordAuditTrail(
    PluginPermission permission,
    String action, {
    bool granted = true,
    String? detail,
  }) {
    if (_auditTrail.length >= 100) {
      _auditTrail.removeAt(0);
    }
    final record = PermissionAuditRecord(
      timestamp: DateTime.now(),
      permission: permission,
      action: action,
      granted: granted,
      detail: detail,
    );
    _auditTrail.add(record);
    recordLog('🔒 [AUDIT] ${record.toString().substring(11)}');
  }

  /// 清空权限审计轨迹
  void clearAuditTrail() {
    _auditTrail.clear();
  }
}
