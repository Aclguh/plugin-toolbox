import 'package:logger/logger.dart';
import '../event/event_bus.dart';
import '../event/app_event.dart';
import '../storage/plugin_storage.dart';
import '../model/plugin_category.dart';
import 'tool_plugin.dart';
import 'dynamic_plugin.dart';
import 'plugin_context.dart';
import '../installer/plugin_installer.dart';

class PluginRegistry {
  PluginRegistry({
    required this.eventBus,
    required this.storageFactory,
    Logger? logger,
  }) : _logger = logger ?? Logger();

  final EventBus eventBus;
  final PluginStorageFactory storageFactory;
  final Logger _logger;

  final Map<String, ToolPlugin> _plugins = {};
  final Set<String> _disabledPlugins = {};
  final Set<String> _initializedPlugins = {};
  final List<String> _order = [];

  List<String> get pluginOrder => List.unmodifiable(_order);

  void loadOrder(List<String> savedOrder) {
    _order.clear();
    for (final id in savedOrder) {
      if (_plugins.containsKey(id) && !_order.contains(id)) {
        _order.add(id);
      }
    }
    for (final id in _plugins.keys) {
      if (!_order.contains(id)) {
        _order.add(id);
      }
    }
  }

  void reorder(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _order.length) return;
    if (newIndex < 0 || newIndex >= _order.length) return;
    if (oldIndex == newIndex) return;
    final item = _order.removeAt(oldIndex);
    _order.insert(newIndex, item);
  }

  void reorderEnabled(int oldIndex, int newIndex) {
    final enabled = enabledPlugins;
    if (oldIndex < 0 || oldIndex >= enabled.length) return;
    if (newIndex < 0 || newIndex >= enabled.length) return;
    if (oldIndex == newIndex) return;

    final movingId = enabled[oldIndex].id;
    final targetId = enabled[newIndex].id;

    _order.remove(movingId);
    final targetPos = _order.indexOf(targetId);
    if (targetPos == -1) {
      _order.add(movingId);
    } else if (oldIndex < newIndex) {
      _order.insert(targetPos + 1, movingId);
    } else {
      _order.insert(targetPos, movingId);
    }
  }

  void register(ToolPlugin plugin) {
    _plugins[plugin.id] = plugin;
    if (!_order.contains(plugin.id)) {
      _order.add(plugin.id);
    }
    _logger.i('Registered plugin: ${plugin.id} (dynamic: ${plugin.isDynamic})');
  }

  void registerAll(List<ToolPlugin> plugins) {
    for (final p in plugins) {
      register(p);
    }
  }

  Future<void> unregister(String pluginId) async {
    _order.remove(pluginId);
    final plugin = _plugins.remove(pluginId);
    if (plugin != null) {
      if (_initializedPlugins.contains(pluginId)) {
        await plugin.dispose();
        _initializedPlugins.remove(pluginId);
      }
      _disabledPlugins.remove(pluginId);
      if (plugin is DynamicPlugin) {
        await PluginInstaller.uninstall(pluginId);
      }
      eventBus.fire(PluginUninstalledEvent(pluginId));
      _logger.i('Unregistered & uninstalled plugin: $pluginId');
    }
  }

  Future<void> initializeAll() async {
    for (final plugin in _plugins.values) {
      if (!_disabledPlugins.contains(plugin.id) && !_initializedPlugins.contains(plugin.id)) {
        await _initPlugin(plugin);
      }
    }
  }

  Future<void> _initPlugin(ToolPlugin plugin) async {
    try {
      final context = PluginContext(
        pluginId: plugin.id,
        storage: storageFactory.create(plugin.id),
        eventBus: eventBus,
        logger: _logger,
        grantedPermissions: plugin is DynamicPlugin
            ? plugin.manifest.permissions.toSet()
            : {},
      );
      await plugin.initialize(context);
      _initializedPlugins.add(plugin.id);
    } catch (e, st) {
      _logger.e('Failed to init plugin [${plugin.id}]', error: e, stackTrace: st);
    }
  }

  List<ToolPlugin> get allPlugins {
    final list = <ToolPlugin>[];
    for (final id in _order) {
      final p = _plugins[id];
      if (p != null) list.add(p);
    }
    for (final entry in _plugins.entries) {
      if (!_order.contains(entry.key)) {
        list.add(entry.value);
      }
    }
    return List.unmodifiable(list);
  }

  List<ToolPlugin> get enabledPlugins =>
      allPlugins.where((p) => !_disabledPlugins.contains(p.id)).toList();

  Map<PluginCategory, List<ToolPlugin>> get pluginsByCategory {
    final map = <PluginCategory, List<ToolPlugin>>{};
    for (final plugin in enabledPlugins) {
      map.putIfAbsent(plugin.category, () => []).add(plugin);
    }
    return map;
  }

  ToolPlugin? getPlugin(String id) => _plugins[id];
  bool isEnabled(String id) => !_disabledPlugins.contains(id);

  Future<void> setEnabled(String id, bool enabled) async {
    if (enabled) {
      _disabledPlugins.remove(id);
      final plugin = _plugins[id];
      if (plugin != null && !_initializedPlugins.contains(id)) {
        await _initPlugin(plugin);
      }
    } else {
      _disabledPlugins.add(id);
      final plugin = _plugins[id];
      if (plugin != null && _initializedPlugins.contains(id)) {
        await plugin.dispose();
        _initializedPlugins.remove(id);
      }
    }
    eventBus.fire(PluginStateChangedEvent(id, enabled));
  }
}
