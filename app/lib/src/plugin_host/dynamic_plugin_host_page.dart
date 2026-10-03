import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';
import 'package:plugin_toolbox_lua/plugin_toolbox_lua.dart';
import 'package:plugin_toolbox_dui/plugin_toolbox_dui.dart';
import 'package:plugin_toolbox_ui/plugin_toolbox_ui.dart';

class DynamicPluginHostPage extends StatefulWidget {
  final DynamicPlugin plugin;

  const DynamicPluginHostPage({super.key, required this.plugin});

  @override
  State<DynamicPluginHostPage> createState() => _DynamicPluginHostPageState();
}

class _DynamicPluginHostPageState extends State<DynamicPluginHostPage>
    implements LuaHostDelegate, DuiActionExecutor {
  late final DuiState _duiState;
  late final DuiEventHandler _eventHandler;
  late final DuiRenderer _renderer;
  LuaPluginRunner? _runner;

  Map<String, dynamic>? _uiRootNode;
  String? _loadError;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _duiState = DuiState();
    _eventHandler = DuiEventHandler(state: _duiState, executor: this);
    _renderer = DuiRenderer(
      state: _duiState,
      eventHandler: _eventHandler,
      pluginRootDir: widget.plugin.rootDir,
    );

    _duiState.addListener(() {
      if (mounted) setState(() {});
    });

    _startPlugin();
  }

  Future<void> _startPlugin() async {
    try {
      // 1. 读取并解析 UI JSON 描述
      final uiFile = widget.plugin.uiDefinitionFile;
      if (!uiFile.existsSync()) {
        throw Exception('未找到 UI 定义文件: ${uiFile.path}');
      }
      final uiJsonStr = uiFile.readAsStringSync();
      _uiRootNode = json.decode(uiJsonStr) as Map<String, dynamic>;

      // 2. 初始化 Lua 运行时
      _runner = LuaPluginRunner(plugin: widget.plugin, delegate: this);
      _runner!.start();

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _loadError = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
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

  // --- LuaHostDelegate 协议 ---
  @override
  void onStateChanged(String key, dynamic value) {
    _duiState.set(key, value);
  }

  @override
  dynamic getState(String key) => _duiState.get(key);

  @override
  Map<String, dynamic> getAllStates() => _duiState.getAll();

  @override
  void showToast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Future<void> showAlert(String title, String message) async {
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  @override
  Future<bool> showConfirm(String title, String message) async {
    if (!mounted) return false;
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    return res ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return PluginPageScaffold(
      title: widget.plugin.name,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? ErrorView(message: '插件运行错误:\n$_loadError')
              : _uiRootNode != null
                  ? _renderer.buildWidget(context, _uiRootNode!)
                  : const Center(child: Text('无 UI 描述')),
    );
  }
}
