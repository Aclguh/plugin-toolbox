import '../model/plugin_permission.dart';
import '../model/plugin_manifest.dart';

/// 权限管理器：管理插件在运行时的授权、撤销与权限校验
class PermissionManager {
  final Map<String, Set<PluginPermission>> _grantedPermissions = {};

  /// 检查插件 [pluginId] 是否存在已配置的自定义/持久化权限
  bool hasCustomPermissions(String pluginId) {
    return _grantedPermissions.containsKey(pluginId);
  }

  /// 检查插件 [pluginId] 是否已被授予 [permission] 权限
  bool hasPermission(String pluginId, PluginPermission permission) {
    return _grantedPermissions[pluginId]?.contains(permission) ?? false;
  }

  /// 获取插件 [pluginId] 当前已授予的所有权限集合（返回不可变视图）
  Set<PluginPermission> getPermissions(String pluginId) {
    return Set.unmodifiable(_grantedPermissions[pluginId] ?? {});
  }

  /// 为插件 [pluginId] 覆盖设置一组完整权限 [permissions]
  void setPermissions(String pluginId, Iterable<PluginPermission> permissions) {
    _grantedPermissions[pluginId] = Set<PluginPermission>.from(permissions);
  }

  /// 为插件 [pluginId] 授予一组权限 [permissions]（支持重复授权幂等）
  void grantPermissions(
      String pluginId, Iterable<PluginPermission> permissions) {
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

  /// 插件更新升级场景：将新版本 Manifest 中声明的非敏感权限自动合并并入已授予集合
  void mergeNonSensitive(
      String pluginId, Iterable<PluginPermission> manifestPermissions) {
    final current = _grantedPermissions.putIfAbsent(pluginId, () => {});
    for (final perm in manifestPermissions) {
      if (!perm.isSensitive) {
        current.add(perm);
      }
    }
  }

  /// 批量从持久化字典加载权限映射
  void loadFromMap(Map<String, Set<PluginPermission>> permissionsMap) {
    _grantedPermissions.clear();
    for (final entry in permissionsMap.entries) {
      _grantedPermissions[entry.key] = Set.from(entry.value);
    }
  }

  /// 导出当前全量权限字典的深拷贝不可变副本
  Map<String, Set<PluginPermission>> toMap() {
    return _grantedPermissions.map((k, v) => MapEntry(k, Set.unmodifiable(v)));
  }

  /// 清除插件 [pluginId] 的所有权限授权记录
  void clearForPlugin(String pluginId) {
    _grantedPermissions.remove(pluginId);
  }
}
