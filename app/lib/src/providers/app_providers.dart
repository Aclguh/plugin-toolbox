import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

final eventBusProvider = Provider<EventBus>((ref) {
  final bus = EventBusImpl();
  ref.onDispose(() => bus.dispose());
  return bus;
});

final storageFactoryProvider = Provider<PluginStorageFactory>((ref) {
  return const PluginStorageFactory();
});

class PluginRegistryNotifier extends StateNotifier<PluginRegistry> {
  PluginRegistryNotifier(super.state);

  static const _orderKey = 'plugin_toolbox_plugin_order';

  @override
  bool updateShouldNotify(PluginRegistry old, PluginRegistry current) => true;

  void refresh() {
    state = state;
  }

  Future<void> saveOrder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_orderKey, state.pluginOrder);
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
  final registry = PluginRegistry(
    eventBus: bus,
    storageFactory: storageFactory,
  );
  return PluginRegistryNotifier(registry);
});

class OrientationNotifier extends StateNotifier<bool> {
  OrientationNotifier() : super(false);

  static const _key = 'auto_rotate_screen';

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final autoRotate = prefs.getBool(_key) ?? false;
      state = autoRotate;
      await _applyOrientation(autoRotate);
    } catch (_) {}
  }

  Future<void> toggle(bool enabled) async {
    state = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, enabled);
      await _applyOrientation(enabled);
    } catch (_) {}
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
  final notifier = OrientationNotifier();
  notifier.init();
  return notifier;
});

/// 应用启动时载入已安装的动态插件并进行初始化
final appInitFutureProvider = FutureProvider<void>((ref) async {
  // 1. 初始化屏幕旋转偏好
  await ref.read(autoRotateProvider.notifier).init();

  final registry = ref.read(pluginRegistryProvider);
  
  // 2. 扫描沙箱中的 .ptx 安装插件
  final installedPlugins = await PluginLoader.loadAllInstalledPlugins();
  registry.registerAll(installedPlugins);

  // 3. 加载持久化的插件排序
  try {
    final prefs = await SharedPreferences.getInstance();
    final savedOrder = prefs.getStringList(PluginRegistryNotifier._orderKey);
    if (savedOrder != null && savedOrder.isNotEmpty) {
      registry.loadOrder(savedOrder);
    }
  } catch (_) {}

  // 4. 初始化所有插件
  await registry.initializeAll();
});
