import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    with WidgetsBindingObserver
    implements LuaHostDelegate, DuiActionExecutor {
  static const MethodChannel _nativeChannel =
      MethodChannel('com.plugintoolbox/host_native');

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
    WidgetsBinding.instance.addObserver(this);
    _duiState = DuiState();
    _eventHandler = DuiEventHandler(state: _duiState, executor: this);
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
      _runner?.onPause();
    }
  }

  Future<void> _startPlugin() async {
    try {
      // 1. 读取并解析 UI JSON 描述（异步读取，避免阻塞 UI 线程）
      final uiJsonStr = await widget.plugin.uiDefinitionFile.readAsString();
      final decoded = json.decode(uiJsonStr);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('UI 描述文件必须是 JSON 对象');
      }
      _uiRootNode = decoded;

      // 2. 初始化 Lua 运行时
      _runner = LuaPluginRunner(plugin: widget.plugin, delegate: this);
      await _runner!.start();

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
  void hideKeyboard() {
    if (mounted) {
      FocusScope.of(context).unfocus();
    }
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
  Future<void> shareText(String text, {String? subject}) async {
    try {
      await _nativeChannel.invokeMethod('shareText', {
        'text': text,
        'subject': subject,
      });
    } catch (_) {}
  }

  @override
  Future<bool> openUrl(String url) async {
    try {
      final res = await _nativeChannel.invokeMethod<bool>('openUrl', {
        'url': url,
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String?> pickFile({List<String>? allowedExtensions}) async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: (allowedExtensions != null && allowedExtensions.isNotEmpty)
            ? FileType.custom
            : FileType.any,
        allowedExtensions: allowedExtensions,
      );
      if (res == null || res.files.isEmpty) return null;
      final file = res.files.first;
      final srcPath = file.path;
      if (srcPath == null) return null;

      final rootDir = widget.plugin.rootDir;
      final fileName = file.name;
      final destDir = Directory('${rootDir.path}/data');
      if (!destDir.existsSync()) {
        destDir.createSync(recursive: true);
      }
      final destFile = File('${destDir.path}/$fileName');
      await File(srcPath).copy(destFile.path);
      return 'data/$fileName';
    } catch (_) {
      return null;
    }
  }

  @override
  Future<String?> pickImage() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.image,
      );
      if (res == null || res.files.isEmpty) return null;
      final file = res.files.first;
      final srcPath = file.path;
      if (srcPath == null) return null;

      final rootDir = widget.plugin.rootDir;
      final fileName = file.name;
      final destDir = Directory('${rootDir.path}/data');
      if (!destDir.existsSync()) {
        destDir.createSync(recursive: true);
      }
      final destFile = File('${destDir.path}/$fileName');
      await File(srcPath).copy(destFile.path);
      return 'data/$fileName';
    } catch (_) {
      return null;
    }
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
                  // 渲染器顶层已通过 ListenableBuilder 订阅状态，无需手动 setState
                  ? _renderer.build(context, _uiRootNode!)
                  : const Center(child: Text('无 UI 描述')),
    );
  }
}
