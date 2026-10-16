import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:logger/logger.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';
import 'package:plugin_toolbox_lua/plugin_toolbox_lua.dart';
import 'package:plugin_toolbox_dui/plugin_toolbox_dui.dart';
import 'package:plugin_toolbox_ui/plugin_toolbox_ui.dart';

import '../providers/app_providers.dart';
import 'plugin_native_bridge.dart';
import 'plugin_dialog_service.dart';
import 'desktop_simulation_adapter.dart';
import 'plugin_host_ai_delegate.dart';
import 'plugin_host_media_delegate.dart';
import 'plugin_host_system_delegate.dart';
import 'plugin_permission_prompt.dart';
import 'plugin_diagnostic_sheet.dart';

/// 动态插件宿主页面容器
class DynamicPluginHostPage extends ConsumerStatefulWidget {
  final DynamicPlugin plugin;

  /// 跨插件调起（plugin.open）携带的初始参数，经路由 extra 贯通至此
  final Map<String, dynamic>? initialData;

  const DynamicPluginHostPage({
    super.key,
    required this.plugin,
    this.initialData,
  });

  @override
  ConsumerState<DynamicPluginHostPage> createState() =>
      _DynamicPluginHostPageState();
}

class _DynamicPluginHostPageState extends ConsumerState<DynamicPluginHostPage>
    with
        WidgetsBindingObserver,
        PluginHostMediaDelegate,
        PluginHostSystemDelegate,
        PluginHostAiDelegate
    implements LuaHostDelegate, DuiActionExecutor {
  late final PluginNativeBridge _nativeBridge;
  late final DuiState _duiState;
  late final DuiEventHandler _eventHandler;
  late final DuiRenderer _renderer;
  LuaPluginRunner? _runner;

  Map<String, dynamic>? _uiRootNode;
  String? _loadError;
  bool _isLoading = true;

  @override
  PluginNativeBridge get nativeBridge => _nativeBridge;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _nativeBridge = PluginNativeBridge(
      pluginRootDir: widget.plugin.rootDir,
      storageQuotaMb: widget.plugin.manifest.storageQuotaMb,
    );
    _duiState = DuiState();
    _eventHandler = DuiEventHandler(
      state: _duiState,
      executor: this,
      permissionChecker: (perm) =>
          widget.plugin.context?.hasPermission(perm) ?? false,
    );
    _renderer = DuiRenderer(
      state: _duiState,
      eventHandler: _eventHandler,
      pluginRootDir: widget.plugin.rootDir,
    );

    _startPlugin();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _runner?.onResume();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _nativeBridge.stopSensor('all');
      _runner?.onPause();
    }
  }

  Future<void> _startPlugin() async {
    try {
      // 0. 上下文懒初始化收敛在页面生命周期内（路由 builder 不做副作用），
      // 深链直达或异步跳转挂载时同样保证上下文就绪
      final registry = ref.read(pluginRegistryProvider);
      if (!registry.isInitialized(widget.plugin.id)) {
        await registry.initializePlugin(widget.plugin.id);
      }
      // 注册表初始化失败（或直接挂载未走注册表）时的兜底上下文
      if (widget.plugin.context == null) {
        await widget.plugin.initialize(PluginContext(
          pluginId: widget.plugin.id,
          storage: const PluginStorageFactory().create(
            widget.plugin.id,
            rootDir: widget.plugin.rootDir,
          ),
          eventBus: EventBusImpl(),
          logger: Logger(),
          grantedPermissions: widget.plugin.manifest.permissions.toSet(),
          rootDir: widget.plugin.rootDir,
          storageQuotaMb: widget.plugin.manifest.storageQuotaMb,
          allowedDomains: widget.plugin.manifest.allowedDomains,
        ));
      }

      // 1. 读取并解析 UI JSON 描述（异步读取，避免阻塞 UI 线程）
      final uiJsonStr = await widget.plugin.uiDefinitionFile.readAsString();
      final decoded = json.decode(uiJsonStr);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('UI 描述文件必须是 JSON 对象');
      }
      _uiRootNode = decoded;

      // 1.5 声明式状态自动持久化：从插件独立沙箱读取持久化快照并预置进入 DUI 状态
      final storage = widget.plugin.context?.storage;
      final persistKeys = <String>{
        ...widget.plugin.manifest.persistentStates,
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
      _runner = LuaPluginRunner(plugin: widget.plugin, delegate: this);
      await _runner!.start();

      // 3. 贯通跨插件调起的初始参数：预置 DUI 状态使 ${state.xxx} 绑定
      // 可直接渲染，并派发 onLaunch 钩子让 Lua 脚本感知调起来源
      final launchData = widget.initialData;
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

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadError = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final storage = widget.plugin.context?.storage;
    if (storage != null && _duiState.persistentKeys.isNotEmpty) {
      for (final k in _duiState.persistentKeys) {
        final val = _duiState.get(k);
        if (val != null) {
          storage.set(k, val);
        }
      }
    }
    _nativeBridge.dispose();
    _runner?.dispose();
    _duiState.dispose();
    super.dispose();
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

  // --- LuaHostDelegate: UI 弹窗与用户交互 (委托至 PluginDialogService) ---
  @override
  void showToast(String message) {
    if (mounted) PluginDialogService.showToast(context, message);
  }

  @override
  Future<void> showAlert(String title, String message) async {
    if (mounted) await PluginDialogService.showAlert(context, title, message);
  }

  @override
  Future<bool> showConfirm(String title, String message) async {
    if (!mounted) return false;
    return await PluginDialogService.showConfirm(context, title, message);
  }

  @override
  Future<String?> showPrompt({
    required String title,
    String? hint,
    String? defaultValue,
  }) async {
    if (!mounted) return null;
    return await PluginDialogService.showPrompt(
      context,
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
    if (!mounted) return null;
    return await PluginDialogService.showPickItem(
      context,
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
    if (!mounted) return null;
    return await PluginDialogService.showBottomSheet(
      context,
      title: title,
      items: items,
    );
  }

  @override
  void hideKeyboard() {
    if (mounted) {
      FocusScope.of(context).unfocus();
    }
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
    if (!mounted) return null;
    return await PluginDialogService.pickDate(
      context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
    );
  }

  @override
  Future<String?> pickTime({String? initialTime}) async {
    if (!mounted) return null;
    return await PluginDialogService.pickTime(
      context,
      initialTime: initialTime,
    );
  }

  @override
  Future<bool> openPlugin(
    String targetPluginId, {
    Map<String, dynamic>? initialData,
  }) async {
    if (!mounted) return false;
    try {
      await context.push('/plugin/$targetPluginId', extra: initialData);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _ensurePermission(PluginPermission perm) async {
    final granted = widget.plugin.context?.hasPermission(perm) ?? false;
    if (granted) return true;
    if (!mounted) return false;
    return await PluginPermissionPrompt.requestPermission(
      context,
      plugin: widget.plugin,
      permission: perm,
      ref: ref,
    );
  }

  @override
  Future<String?> scanBarcode({String? prompt}) async {
    if (!await _ensurePermission(PluginPermission.camera)) return null;
    final res = await nativeBridge.scanBarcode(prompt: prompt);
    if (res != null) return res;
    if (!mounted) return null;
    return await DesktopSimulationAdapter.simulateScanBarcode(context,
        prompt: prompt);
  }

  @override
  Future<String?> decodeBarcodeFromImage(String filePath) async {
    final res = await nativeBridge.decodeBarcodeFromImage(filePath);
    if (res != null) return res;
    if (!mounted) return null;
    return await DesktopSimulationAdapter.simulateDecodeBarcode(context);
  }

  @override
  Widget build(BuildContext context) {
    return PluginPageScaffold(
      title: widget.plugin.name,
      actions: [
        IconButton(
          icon: const Icon(Icons.bug_report_outlined),
          tooltip: '运行诊断与控制台',
          onPressed: () {
            PluginDiagnosticSheet.show(
              context,
              plugin: widget.plugin,
              runner: _runner,
              onReload: () {
                setState(() {
                  _isLoading = true;
                  _loadError = null;
                });
                _runner?.dispose();
                _runner = null;
                _startPlugin();
              },
            );
          },
        ),
      ],
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? ErrorView(message: '插件运行错误:\n$_loadError')
              : _uiRootNode != null
                  ? _renderer.build(context, _uiRootNode!)
                  : const Center(child: Text('无 UI 描述')),
    );
  }
}
