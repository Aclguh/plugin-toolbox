import 'dart:async';

import 'package:logger/logger.dart';
import '../event/event_bus.dart';
import '../event/app_event.dart';
import '../storage/plugin_storage.dart';
import '../model/plugin_category.dart';
import 'tool_plugin.dart';
import 'dynamic_plugin.dart';
import 'plugin_context.dart';
import 'plugin_list_controller.dart';

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

  /// 排序与排列细节委托给独立控制器，注册中心只保留生命周期职责
  final PluginListController _orderController = PluginListController();

  /// 启禁用状态变动频繁而读取高频（每次 UI 重建都会访问），
  /// 缓存列表并在任何注册/注销/排序/启禁用变更后失效，避免重复重算与 GC 压力
  List<ToolPlugin>? _cachedAll;
  List<ToolPlugin>? _cachedEnabled;

  void _invalidateCaches() {
    _cachedAll = null;
    _cachedEnabled = null;
  }

  List<String> get pluginOrder => _orderController.order;

  void loadOrder(List<String> savedOrder) {
    _orderController.loadOrder(_plugins.keys.toSet(), savedOrder);
    _invalidateCaches();
  }

  void reorder(int oldIndex, int newIndex) {
    _orderController.reorder(oldIndex, newIndex);
    _invalidateCaches();
  }

  void reorderEnabled(int oldIndex, int newIndex) {
    _orderController.reorderEnabled(
      enabledPlugins.map((p) => p.id).toList(),
      oldIndex,
      newIndex,
    );
    _invalidateCaches();
  }

  void register(ToolPlugin plugin) {
    final existing = _plugins[plugin.id];
    // 同 ID 覆盖 (导入新版 .ptx 即插件更新): 已初始化的旧实例必须先弃用。
    // 否则新实例会被 initializeAll 的"按 ID 去重"过滤跳过, 永远拿不到
    // PluginContext, 打开插件时被 LuaPluginRunner 的守卫拒绝启动。
    if (existing != null &&
        existing != plugin &&
        _initializedPlugins.contains(plugin.id)) {
      _initializedPlugins.remove(plugin.id);
      unawaited(existing.dispose());
    }
    _plugins[plugin.id] = plugin;
    _orderController.add(plugin.id);
    _invalidateCaches();
    _logger.i('Registered plugin: ${plugin.id} (dynamic: ${plugin.isDynamic})');
  }

  void registerAll(List<ToolPlugin> plugins) {
    for (final p in plugins) {
      register(p);
    }
  }

  Future<void> unregister(String pluginId) async {
    _orderController.remove(pluginId);
    final plugin = _plugins.remove(pluginId);
    if (plugin != null) {
      if (_initializedPlugins.contains(pluginId)) {
        await plugin.dispose();
        _initializedPlugins.remove(pluginId);
      }
      _disabledPlugins.remove(pluginId);
      _invalidateCaches();
      if (plugin is DynamicPlugin) {
        // 注册中心不直接触碰文件系统：发出卸载请求，由安装器监听执行沙箱清理
        eventBus.fire(PluginUninstallRequestedEvent(pluginId));
      }
      eventBus.fire(PluginUninstalledEvent(pluginId));
      _logger.i('Unregistered & uninstalled plugin: $pluginId');
    }
  }

  Future<void> initializeAll() async {
    // 并发初始化：单个慢插件不再拖慢整体启动耗时
    final pending = _plugins.values
        .where((p) =>
            !_disabledPlugins.contains(p.id) &&
            !_initializedPlugins.contains(p.id))
        .map(_initPlugin)
        .toList();
    await Future.wait(pending);
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
        rootDir: plugin is DynamicPlugin ? plugin.rootDir : null,
      );
      await plugin.initialize(context);
      _initializedPlugins.add(plugin.id);
    } catch (e, st) {
      _logger.e('Failed to init plugin [${plugin.id}]', error: e, stackTrace: st);
    }
  }

  List<ToolPlugin> get allPlugins {
    final cached = _cachedAll;
    if (cached != null) return cached;

    final list = <ToolPlugin>[];
    final orderedSet = _orderController.order.toSet();
    for (final id in _orderController.order) {
      final p = _plugins[id];
      if (p != null) list.add(p);
    }
    for (final entry in _plugins.entries) {
      if (!orderedSet.contains(entry.key)) {
        list.add(entry.value);
      }
    }
    _cachedAll = List.unmodifiable(list);
    return _cachedAll!;
  }

  List<ToolPlugin> get enabledPlugins {
    final cached = _cachedEnabled;
    if (cached != null) return cached;
    _cachedEnabled =
        List.unmodifiable(allPlugins.where((p) => !_disabledPlugins.contains(p.id)));
    return _cachedEnabled!;
  }

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
    _invalidateCaches();
    eventBus.fire(PluginStateChangedEvent(id, enabled));
  }
}
