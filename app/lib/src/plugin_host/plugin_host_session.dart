import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:logger/logger.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';
import 'package:plugin_toolbox_dui/plugin_toolbox_dui.dart';
import 'package:plugin_toolbox_lua/plugin_toolbox_lua.dart';

import 'plugin_native_bridge.dart';
import 'plugin_host_ai_delegate.dart';
import 'plugin_host_media_delegate.dart';
import 'plugin_host_system_delegate.dart';

/// 插件宿主会话生命周期与加载状态
enum PluginSessionStatus {
  loading,
  ready,
  error,
}

/// 宿主与视图层解耦的用户交互协议 (UI / 弹窗 / 软键盘 / 扫码模拟 / 权限申请)
abstract class PluginSessionUiHandler {
  void showToast(String message);
  Future<void> showAlert(String title, String message);
  Future<bool> showConfirm(String title, String message);
  Future<String?> showPrompt({
    required String title,
    String? hint,
    String? defaultValue,
  });
  Future<Map<String, dynamic>?> showPickItem({
    required String title,
    required List<String> items,
    int initialIndex = 0,
  });
  Future<Map<String, dynamic>?> showBottomSheet({
    required String title,
    required List<String> items,
  });
  void hideKeyboard();
  Future<String?> pickDate({
    String? initialDate,
    String? firstDate,
    String? lastDate,
  });
  Future<String?> pickTime({String? initialTime});
  Future<bool> openPlugin(
    String targetPluginId, {
    Map<String, dynamic>? initialData,
  });
  Future<bool> requestPermission(PluginPermission permission);
  Future<String?> simulateScanBarcode({String? prompt});
  Future<String?> simulateDecodeBarcode();
}

/// 动态插件宿主会话控制器
///
/// 统一管理原生桥接 (NativeBridge)、DUI 状态、渲染器、Lua 运行时以及会话生命周期。
/// 与具体 Widget 树解耦，支持无界面环境的直接实例化与单元测试。
class PluginHostSession extends ChangeNotifier
    with PluginHostMediaDelegate, PluginHostSystemDelegate, PluginHostAiDelegate
    implements LuaHostDelegate, DuiActionExecutor {
  final DynamicPlugin plugin;
  final Map<String, dynamic>? initialData;
  PluginSessionUiHandler? uiHandler;

  late final PluginNativeBridge _nativeBridge;
  late final DuiState _duiState;
  late final DuiEventHandler _eventHandler;
  late final DuiRenderer _renderer;
  LuaPluginRunner? _runner;

  Map<String, dynamic>? _uiRootNode;
  PluginSessionStatus _status = PluginSessionStatus.loading;
  String? _errorMessage;

  PluginHostSession({
    required this.plugin,
    this.initialData,
    this.uiHandler,
    PluginNativeBridge? nativeBridge,
    DuiState? duiState,
  }) {
    _nativeBridge = nativeBridge ??
        PluginNativeBridge(
          pluginRootDir: plugin.rootDir,
          storageQuotaMb: plugin.manifest.storageQuotaMb,
        );
    _duiState = duiState ?? DuiState();
    _eventHandler = DuiEventHandler(
      state: _duiState,
      executor: this,
      permissionChecker: (perm) => plugin.context?.hasPermission(perm) ?? false,
    );
    _renderer = DuiRenderer(
      state: _duiState,
      eventHandler: _eventHandler,
      pluginRootDir: plugin.rootDir,
    );
  }

  @override
  PluginNativeBridge get nativeBridge => _nativeBridge;

  DuiState get duiState => _duiState;
  DuiEventHandler get eventHandler => _eventHandler;
  DuiRenderer get renderer => _renderer;
  LuaPluginRunner? get runner => _runner;
  Map<String, dynamic>? get uiRootNode => _uiRootNode;
  PluginSessionStatus get status => _status;
  String? get errorMessage => _errorMessage;
  bool get isLoading => _status == PluginSessionStatus.loading;
  bool get isReady => _status == PluginSessionStatus.ready;
  bool get hasError => _status == PluginSessionStatus.error;

  /// 启动并初始化插件会话
  Future<void> start({PluginRegistry? registry}) async {
    try {
      _status = PluginSessionStatus.loading;
      _errorMessage = null;
      notifyListeners();

      // 0. 上下文懒初始化与兜底保证
      if (registry != null && !registry.isInitialized(plugin.id)) {
        await registry.initializePlugin(plugin.id);
      }
      if (plugin.context == null) {
        await plugin.initialize(PluginContext(
          pluginId: plugin.id,
          storage: const PluginStorageFactory().create(
            plugin.id,
            rootDir: plugin.rootDir,
          ),
          eventBus: EventBusImpl(),
          logger: Logger(),
          grantedPermissions: plugin.manifest.permissions.toSet(),
          rootDir: plugin.rootDir,
          storageQuotaMb: plugin.manifest.storageQuotaMb,
          allowedDomains: plugin.manifest.allowedDomains,
        ));
      }

      // 1. 读取并解析 UI JSON 描述 (优先使用 AST 内存缓存)
      _uiRootNode = await plugin.loadUiDefinition();

      // 1.5 声明式状态自动持久化恢复与监听
      final storage = plugin.context?.storage;
      final persistKeys = <String>{
        ...plugin.manifest.persistentStates,
        if (_uiRootNode?['props'] is Map &&
            _uiRootNode!['props']['persistentStates'] is List)
          ...(_uiRootNode!['props']['persistentStates'] as List)
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty),
      };
      if (persistKeys.isNotEmpty && storage != null) {
        _duiState.persistentKeys.addAll(persistKeys);
        for (final k in persistKeys) {
          final saved = await storage.get(k);
          if (saved != null) {
            _duiState.set(k, saved);
          }
        }
        _duiState.onPersist = (k, v) {
          storage.set(k, v);
        };
      }

      // 2. 初始化 Lua 运行时
      _runner = LuaPluginRunner(plugin: plugin, delegate: this);
      await _runner!.start();

      // 3. 贯通跨插件调起的初始参数
      final launchData = initialData;
      if (launchData != null && launchData.isNotEmpty) {
        for (final entry in launchData.entries) {
          _duiState.set(entry.key, entry.value);
        }
        try {
          _runner!.dispatchAction('onLaunch', [launchData]);
        } catch (e) {
          showToast('onLaunch 执行错误: $e');
        }
      }

      _status = PluginSessionStatus.ready;
      notifyListeners();
    } catch (e) {
      _errorMessage = e.toString();
      _status = PluginSessionStatus.error;
      notifyListeners();
    }
  }

  /// 重新加载插件（清空 AST 缓存与重置运行时）
  Future<void> reload({PluginRegistry? registry}) async {
    plugin.invalidateUiCache();
    _runner?.dispose();
    _runner = null;
    await start(registry: registry);
  }

  /// 同步处理应用生命周期变迁
  void handleAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _runner?.onResume();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _nativeBridge.stopSensor('all');
      plugin.context?.storage.flush();
      _runner?.onPause();
    }
  }

  /// 保存当前 DUI 中声明持久化的键值
  void savePersistedStates() {
    final storage = plugin.context?.storage;
    if (storage != null && _duiState.persistentKeys.isNotEmpty) {
      for (final k in _duiState.persistentKeys) {
        final val = _duiState.get(k);
        if (val != null) {
          storage.set(k, val);
        }
      }
    }
    storage?.flush();
  }

  // --- DuiActionExecutor 协议 ---
  @override
  void callLua(String functionName, [List<dynamic> args = const []]) {
    try {
      _runner?.dispatchAction(functionName, args);
    } catch (e) {
      showToast('执行错误: $e');
    }
  }

  // --- LuaHostDelegate: 状态管理 ---
  @override
  void onStateChanged(String key, dynamic value) => _duiState.set(key, value);

  @override
  dynamic getState(String key) => _duiState.get(key);

  @override
  Map<String, dynamic> getAllStates() => _duiState.getAll();

  // --- LuaHostDelegate: UI 弹窗与用户交互 ---
  @override
  void showToast(String message) {
    uiHandler?.showToast(message);
  }

  @override
  Future<void> showAlert(String title, String message) async {
    await uiHandler?.showAlert(title, message);
  }

  @override
  Future<bool> showConfirm(String title, String message) async {
    return await uiHandler?.showConfirm(title, message) ?? false;
  }

  @override
  Future<String?> showPrompt({
    required String title,
    String? hint,
    String? defaultValue,
  }) async {
    return await uiHandler?.showPrompt(
      title: title,
      hint: hint,
      defaultValue: defaultValue,
    );
  }

  @override
  Future<Map<String, dynamic>?> showPickItem({
    required String title,
    required List<String> items,
    int initialIndex = 0,
  }) async {
    return await uiHandler?.showPickItem(
      title: title,
      items: items,
      initialIndex: initialIndex,
    );
  }

  @override
  Future<Map<String, dynamic>?> showBottomSheet({
    required String title,
    required List<String> items,
  }) async {
    return await uiHandler?.showBottomSheet(
      title: title,
      items: items,
    );
  }

  @override
  void hideKeyboard() {
    uiHandler?.hideKeyboard();
  }

  // --- LuaClipboardDelegate 协议实现 ---
  @override
  void setClipboardText(String text) {
    Clipboard.setData(ClipboardData(text: text));
  }

  @override
  Future<String?> getClipboardText() async {
    final data = await Clipboard.getData('text/plain');
    return data?.text;
  }

  @override
  void hapticFeedback(String type) {
    switch (type) {
      case 'light':
        HapticFeedback.lightImpact();
        break;
      case 'medium':
        HapticFeedback.mediumImpact();
        break;
      case 'heavy':
        HapticFeedback.heavyImpact();
        break;
      case 'selection':
        HapticFeedback.selectionClick();
        break;
      case 'vibrate':
      default:
        HapticFeedback.vibrate();
        break;
    }
  }

  @override
  Future<String?> pickDate({
    String? initialDate,
    String? firstDate,
    String? lastDate,
  }) async {
    return await uiHandler?.pickDate(
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
    );
  }

  @override
  Future<String?> pickTime({String? initialTime}) async {
    return await uiHandler?.pickTime(initialTime: initialTime);
  }

  @override
  Future<bool> openPlugin(
    String targetPluginId, {
    Map<String, dynamic>? initialData,
  }) async {
    return await uiHandler?.openPlugin(
          targetPluginId,
          initialData: initialData,
        ) ??
        false;
  }

  Future<bool> ensurePermission(PluginPermission perm) async {
    final granted = plugin.context?.hasPermission(perm) ?? false;
    if (granted) return true;
    return await uiHandler?.requestPermission(perm) ?? false;
  }

  @override
  Future<String?> scanBarcode({String? prompt}) async {
    if (!await ensurePermission(PluginPermission.camera)) return null;
    final res = await nativeBridge.scanBarcode(prompt: prompt);
    if (res != null) return res;
    return await uiHandler?.simulateScanBarcode(prompt: prompt);
  }

  @override
  Future<String?> decodeBarcodeFromImage(String filePath) async {
    final res = await nativeBridge.decodeBarcodeFromImage(filePath);
    if (res != null) return res;
    return await uiHandler?.simulateDecodeBarcode();
  }

  @override
  void dispose() {
    savePersistedStates();
    _nativeBridge.dispose();
    _runner?.dispose();
    _runner = null;
    _duiState.dispose();
    super.dispose();
  }
}
