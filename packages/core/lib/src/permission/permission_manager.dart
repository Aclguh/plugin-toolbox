import '../model/plugin_permission.dart';
import '../model/plugin_manifest.dart';

/// 权限管理器：管理插件在运行时的授权、撤销与权限校验
class PermissionManager {
  final Map<String, Set<PluginPermission>> _grantedPermissions = {};

  /// 检查插件 [pluginId] 是否已被授予 [permission] 权限
  bool hasPermission(String pluginId, PluginPermission permission) {
    return _grantedPermissions[pluginId]?.contains(permission) ?? false;
  }

  /// 获取插件 [pluginId] 当前已授予的所有权限集合（返回不可变视图）
  Set<PluginPermission> getPermissions(String pluginId) {
    return Set.unmodifiable(_grantedPermissions[pluginId] ?? {});
  }

  /// 为插件 [pluginId] 授予一组权限 [permissions]（支持重复授权幂等）
  void grantPermissions(String pluginId, Iterable<PluginPermission> permissions) {
    _grantedPermissions.putIfAbsent(pluginId, () => {}).addAll(permissions);
  }

  /// 撤销插件 [pluginId] 的指定权限 [permission]
  void revokePermission(String pluginId, PluginPermission permission) {
    _grantedPermissions[pluginId]?.remove(permission);
  }

  /// 根据插件清单 [manifest] 初始化插件声明的默认权限
  void initializeForPlugin(PluginManifest manifest) {
    _grantedPermissions[manifest.id] = manifest.permissions.toSet();
  }

  /// 清除插件 [pluginId] 的所有权限授权记录
  void clearForPlugin(String pluginId) {
    _grantedPermissions.remove(pluginId);
  }
}
