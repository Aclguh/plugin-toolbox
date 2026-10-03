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
T safeRead<T>(SharedPreferences prefs, String key, T fallback, T? Function(String) getter) {
  try {
    final value = getter(key);
    return value ?? fallback;
  } catch (_) {
    return fallback;
  }
}

class PluginRegistryNotifier extends StateNotifier<PluginRegistry> {
  PluginRegistryNotifier(super.state, this._prefs);

  final SharedPreferences _prefs;

  static const _orderKey = 'plugin_toolbox_plugin_order';

  @override
  bool updateShouldNotify(PluginRegistry old, PluginRegistry current) => true;

  void refresh() {
    state = state;
  }

  Future<void> saveOrder() async {
    try {
      await _prefs.setStringList(_orderKey, state.pluginOrder);
    } catch (_) {}
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

final pluginRegistryProvider = StateNotifierProvider<PluginRegistryNotifier, PluginRegistry>((ref) {
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
  return PluginRegistryNotifier(registry, prefs);
});

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

final autoRotateProvider = StateNotifierProvider<OrientationNotifier, bool>((ref) {
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

final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
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

final dynamicColorEnabledProvider = StateNotifierProvider<DynamicColorNotifier, bool>((ref) {
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

  // 3. 加载持久化的插件排序
  try {
    final savedOrder = prefs.getStringList(PluginRegistryNotifier._orderKey);
    if (savedOrder != null && savedOrder.isNotEmpty) {
      registry.loadOrder(savedOrder);
    }
  } catch (_) {}

  // 4. 初始化所有插件
  await registry.initializeAll();
});
