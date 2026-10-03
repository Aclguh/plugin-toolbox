import 'package:logger/logger.dart';
import '../event/event_bus.dart';
import '../storage/plugin_storage.dart';
import '../model/plugin_permission.dart';

/// 运行时注入给插件的上下文环境
class PluginContext {
  final String pluginId;
  final PluginStorage storage;
  final EventBus eventBus;
  final Logger logger;
  final Set<PluginPermission> grantedPermissions;

  const PluginContext({
    required this.pluginId,
    required this.storage,
    required this.eventBus,
    required this.logger,
    required this.grantedPermissions,
  });

  bool hasPermission(PluginPermission perm) => grantedPermissions.contains(perm);
}
