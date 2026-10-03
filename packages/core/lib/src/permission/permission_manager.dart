import '../model/plugin_permission.dart';
import '../model/plugin_manifest.dart';

/// 权限管理器：管理插件授权与校验
class PermissionManager {
  final Map<String, Set<PluginPermission>> _grantedPermissions = {};

  bool hasPermission(String pluginId, PluginPermission permission) {
    return _grantedPermissions[pluginId]?.contains(permission) ?? false;
  }

  Set<PluginPermission> getPermissions(String pluginId) {
    return Set.unmodifiable(_grantedPermissions[pluginId] ?? {});
  }

  void grantPermissions(String pluginId, Iterable<PluginPermission> permissions) {
    _grantedPermissions.putIfAbsent(pluginId, () => {}).addAll(permissions);
  }

  void revokePermission(String pluginId, PluginPermission permission) {
    _grantedPermissions[pluginId]?.remove(permission);
  }

  void initializeForPlugin(PluginManifest manifest) {
    _grantedPermissions[manifest.id] = manifest.permissions.toSet();
  }

  void clearForPlugin(String pluginId) {
    _grantedPermissions.remove(pluginId);
  }
}
