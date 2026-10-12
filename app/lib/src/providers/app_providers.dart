import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 统一注入的 SharedPreferences：在 main() 中初始化一次，
/// 各 Notifier 不再各自 await getInstance()，测试中以 override 注入 mock
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
      'sharedPreferencesProvider 必须在应用启动时以 overrideWithValue 注入');
});

final eventBusProvider = Provider<EventBus>((ref) {
  final bus = EventBusImpl();
  ref.onDispose(() => bus.dispose());
  return bus;
});

final storageFactoryProvider = Provider<PluginStorageFactory>((ref) {
  return const PluginStorageFactory();
});

/// SharedPreferences 读取的安全容空包装：存储故障时降级为默认值，绝不崩溃
T safeRead<T>(SharedPreferences prefs, String key, T fallback,
    T? Function(String) getter) {
  try {
    final value = getter(key);
    return value ?? fallback;
  } catch (_) {
    return fallback;
  }
}

class PluginRegistryNotifier extends StateNotifier<PluginRegistry> {
  PluginRegistryNotifier(super.state, this._prefs, {EventBus? eventBus}) {
    if (eventBus != null) {
      _subscription = eventBus.on<AppEvent>().listen((_) {
        refresh();
      });
    }
  }

  final SharedPreferences _prefs;
  StreamSubscription<AppEvent>? _subscription;

  static const _orderKey = 'plugin_toolbox_plugin_order';
  static const _disabledKey = 'plugin_toolbox_disabled_plugins';
  static const _customPermissionsPrefix = 'plugin_toolbox_permissions_';

  @override
  bool updateShouldNotify(PluginRegistry old, PluginRegistry current) => true;

  void refresh() {
    state = state;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> saveOrder() async {
    try {
      await _prefs.setStringList(_orderKey, state.pluginOrder);
    } catch (_) {}
  }

  Future<void> saveDisabledPlugins() async {
    try {
      await _prefs.setStringList(
        _disabledKey,
        state.disabledPluginIds.toList(),
      );
    } catch (_) {}
  }

  Future<void> saveCustomPermissions(
      String pluginId, Set<PluginPermission> permissions) async {
    try {
      final permNames = permissions.map((p) => p.name).toList();
      await _prefs.setStringList(
          '$_customPermissionsPrefix$pluginId', permNames);
    } catch (_) {}
  }

  Future<void> removeCustomPermissions(String pluginId) async {
    try {
      await _prefs.remove('$_customPermissionsPrefix$pluginId');
    } catch (_) {}
  }

  Future<void> setEnabled(String id, bool enabled) async {
    await state.setEnabled(id, enabled);
    state = state;
    await saveDisabledPlugins();
  }

  Future<void> setCustomPermissions(
      String pluginId, Set<PluginPermission> permissions) async {
    state.setCustomPermissions(pluginId, permissions);
    state = state;
    await saveCustomPermissions(pluginId, permissions);
  }

  Future<void> reorder(int oldIndex, int newIndex) async {
    state.reorder(oldIndex, newIndex);
    state = state;
    await saveOrder();
  }

  Future<void> reorderEnabled(int oldIndex, int newIndex) async {
    state.reorderEnabled(oldIndex, newIndex);
    state = state;
    await saveOrder();
  }
}

final pluginRegistryProvider =
    StateNotifierProvider<PluginRegistryNotifier, PluginRegistry>((ref) {
  final bus = ref.watch(eventBusProvider);
  final storageFactory = ref.watch(storageFactoryProvider);
  final prefs = ref.watch(sharedPreferencesProvider);
  final registry = PluginRegistry(
    eventBus: bus,
    storageFactory: storageFactory,
  );
  // 注册中心只发出卸载请求事件，沙箱目录清理由安装器监听执行
  final uninstallSub = PluginInstaller.listenUninstallRequests(bus);
  ref.onDispose(() => uninstallSub.cancel());
  return PluginRegistryNotifier(registry, prefs, eventBus: bus);
});

/// 派生 provider 以 select 订阅注册表内部缓存的列表实例：
/// 注册表仅在注册/注销/排序/启禁用变更后才失效重建缓存列表，
/// 因此无关 EventBus 事件不再触发首页/管理/商店 watcher 重建，
/// 而排序与启禁用变更会重建列表实例，各页面精确联动刷新。
final allPluginListProvider = Provider<List<ToolPlugin>>(
  (ref) => ref.watch(pluginRegistryProvider.select((r) => r.allPlugins)),
);

/// 已启用插件列表（首页网格）：与全量列表同一数据源，
/// 排序/启禁用变更时两处严格实时同步
final enabledPluginListProvider = Provider<List<ToolPlugin>>(
  (ref) => ref.watch(pluginRegistryProvider.select((r) => r.enabledPlugins)),
);

class OrientationNotifier extends StateNotifier<bool> {
  OrientationNotifier(SharedPreferences prefs)
      : _prefs = prefs,
        super(safeRead(prefs, _key, false, prefs.getBool));

  final SharedPreferences _prefs;

  static const _key = 'auto_rotate_screen';

  /// 应用当前偏好到系统方向设置（偏好本身在构造时已同步载入）
  Future<void> init() async {
    await _applyOrientation(state);
  }

  Future<void> toggle(bool enabled) async {
    state = enabled;
    try {
      await _prefs.setBool(_key, enabled);
    } catch (_) {}
    await _applyOrientation(enabled);
  }

  Future<void> _applyOrientation(bool autoRotate) async {
    if (autoRotate) {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
    }
  }
}

final autoRotateProvider =
    StateNotifierProvider<OrientationNotifier, bool>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return OrientationNotifier(prefs);
});

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier(SharedPreferences prefs)
      : _prefs = prefs,
        super(_load(prefs));

  final SharedPreferences _prefs;

  static const _key = 'app_theme_mode';

  static ThemeMode _load(SharedPreferences prefs) {
    final modeStr = safeRead(prefs, _key, 'dark', prefs.getString);
    return switch (modeStr) {
      'light' => ThemeMode.light,
      'system' => ThemeMode.system,
      _ => ThemeMode.dark,
    };
  }

  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    try {
      final modeStr = switch (mode) {
        ThemeMode.light => 'light',
        ThemeMode.system => 'system',
        ThemeMode.dark => 'dark',
      };
      await _prefs.setString(_key, modeStr);
    } catch (_) {}
  }
}

final themeModeProvider =
    StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return ThemeModeNotifier(prefs);
});

class DynamicColorNotifier extends StateNotifier<bool> {
  DynamicColorNotifier(SharedPreferences prefs)
      : _prefs = prefs,
        super(safeRead(prefs, _key, false, prefs.getBool));

  final SharedPreferences _prefs;

  static const _key = 'use_dynamic_color';

  Future<void> toggle(bool enabled) async {
    state = enabled;
    try {
      await _prefs.setBool(_key, enabled);
    } catch (_) {}
  }
}

final dynamicColorEnabledProvider =
    StateNotifierProvider<DynamicColorNotifier, bool>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return DynamicColorNotifier(prefs);
});

/// 应用启动时载入已安装的动态插件并进行初始化
final appInitFutureProvider = FutureProvider<void>((ref) async {
  // 1. 应用屏幕旋转偏好（主题与动态取色偏好在 Notifier 构造时已同步载入）
  await ref.read(autoRotateProvider.notifier).init();

  final registry = ref.read(pluginRegistryProvider);
  final prefs = ref.read(sharedPreferencesProvider);

  // 2. 扫描沙箱中的 .ptx 安装插件
  final installedPlugins = await PluginLoader.loadAllInstalledPlugins();
  registry.registerAll(installedPlugins);

  // 3. 加载持久化的插件排序、已禁用插件集合与自定义权限配置
  try {
    final savedOrder = prefs.getStringList(PluginRegistryNotifier._orderKey);
    if (savedOrder != null && savedOrder.isNotEmpty) {
      registry.loadOrder(savedOrder);
    }

    final savedDisabled =
        prefs.getStringList(PluginRegistryNotifier._disabledKey);
    if (savedDisabled != null && savedDisabled.isNotEmpty) {
      registry.loadDisabledPlugins(savedDisabled.toSet());
    }

    final permissionsMap = <String, Set<PluginPermission>>{};
    for (final plugin in installedPlugins) {
      final permNames = prefs.getStringList(
          '${PluginRegistryNotifier._customPermissionsPrefix}${plugin.id}');
      if (permNames != null) {
        final perms = permNames
            .map(PluginPermission.fromString)
            .whereType<PluginPermission>()
            .toSet();
        permissionsMap[plugin.id] = perms;
      }
    }
    if (permissionsMap.isNotEmpty) {
      registry.loadCustomPermissions(permissionsMap);
    }
  } catch (_) {}
});
