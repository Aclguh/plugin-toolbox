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
      stopSensor('all');
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

  bool _torchOn = false;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_torchOn) {
      setTorch(false);
    }
    stopSensor('all');
    stopAudio();
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
  Future<bool> setTorch(bool enabled) async {
    _torchOn = enabled;
    try {
      await _nativeChannel.invokeMethod<bool>('setTorch', {'enabled': enabled});
    } catch (_) {}
    return true;
  }

  @override
  bool get isTorchOn => _torchOn;

  @override
  Future<bool> shareFile(
    String filePath, {
    String? mimeType,
    String? subject,
  }) async {
    try {
      final res = await _nativeChannel.invokeMethod<bool>('shareFile', {
        'path': filePath,
        'mimeType': mimeType,
        'subject': subject,
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> saveToGallery(String filePath) async {
    try {
      final res = await _nativeChannel.invokeMethod<bool>('saveToGallery', {
        'path': filePath,
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> exportFile(String filePath, {String? defaultName}) async {
    try {
      final res = await _nativeChannel.invokeMethod<bool>('exportFile', {
        'path': filePath,
        'defaultName': defaultName,
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String?> pickDate({
    String? initialDate,
    String? firstDate,
    String? lastDate,
  }) async {
    if (!mounted) return null;
    DateTime parseDate(String? s, DateTime fallback) {
      if (s == null || s.isEmpty) return fallback;
      try {
        return DateTime.parse(s);
      } catch (_) {
        return fallback;
      }
    }

    final now = DateTime.now();
    final first = parseDate(firstDate, DateTime(1900, 1, 1));
    final last = parseDate(lastDate, DateTime(2100, 12, 31));
    var init = parseDate(initialDate, now);
    if (init.isBefore(first)) init = first;
    if (init.isAfter(last)) init = last;

    final picked = await showDatePicker(
      context: context,
      initialDate: init,
      firstDate: first,
      lastDate: last,
    );
    if (picked == null) return null;
    final y = picked.year.toString().padLeft(4, '0');
    final m = picked.month.toString().padLeft(2, '0');
    final d = picked.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  @override
  Future<String?> pickTime({String? initialTime}) async {
    if (!mounted) return null;
    TimeOfDay parseTime(String? s) {
      if (s != null && s.contains(':')) {
        final parts = s.split(':');
        final h = int.tryParse(parts[0]);
        final m = int.tryParse(parts[1]);
        if (h != null && m != null) {
          return TimeOfDay(hour: h.clamp(0, 23), minute: m.clamp(0, 59));
        }
      }
      return TimeOfDay.now();
    }

    final picked = await showTimePicker(
      context: context,
      initialTime: parseTime(initialTime),
    );
    if (picked == null) return null;
    final h = picked.hour.toString().padLeft(2, '0');
    final m = picked.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Future<String?> scanBarcode({String? prompt}) async {
    try {
      final res = await _nativeChannel.invokeMethod<String>('scanBarcode', {
        'prompt': prompt,
      });
      return res;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<String?> decodeBarcodeFromImage(String filePath) async {
    try {
      final res = await _nativeChannel.invokeMethod<String>(
        'decodeBarcodeFromImage',
        {'path': filePath},
      );
      return res;
    } catch (_) {
      return null;
    }
  }

  final Map<String, Map<String, dynamic>> _sensorCache = {};

  @override
  Future<bool> startSensor(String type) async {
    try {
      final res = await _nativeChannel.invokeMethod<bool>('startSensor', {
        'type': type,
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> stopSensor(String type) async {
    try {
      final res = await _nativeChannel.invokeMethod<bool>('stopSensor', {
        'type': type,
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<Map<String, dynamic>?> getSensorData(String type) async {
    try {
      final res = await _nativeChannel.invokeMapMethod<String, dynamic>(
        'getSensorData',
        {'type': type},
      );
      if (res != null) {
        _sensorCache[type] = res;
      }
      return res ?? _sensorCache[type];
    } catch (_) {
      return _sensorCache[type];
    }
  }

  // ---- 媒体图像处理 (P2) ----
  @override
  Future<Map<String, dynamic>?> imageInfo(String filePath) async {
    try {
      final res = await _nativeChannel.invokeMapMethod<String, dynamic>(
        'imageInfo',
        {'path': filePath},
      );
      return res;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> compressImage(
    String srcPath,
    String destPath, {
    int quality = 80,
  }) async {
    try {
      final res = await _nativeChannel.invokeMethod<bool>('compressImage', {
        'src': srcPath,
        'dest': destPath,
        'quality': quality,
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> cropImage(
    String srcPath,
    String destPath, {
    required int x,
    required int y,
    required int width,
    required int height,
  }) async {
    try {
      final res = await _nativeChannel.invokeMethod<bool>('cropImage', {
        'src': srcPath,
        'dest': destPath,
        'x': x,
        'y': y,
        'width': width,
        'height': height,
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> convertImage(
    String srcPath,
    String destPath, {
    required String format,
  }) async {
    try {
      final res = await _nativeChannel.invokeMethod<bool>('convertImage', {
        'src': srcPath,
        'dest': destPath,
        'format': format,
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> stripExifImage(String srcPath, String destPath) async {
    try {
      final res = await _nativeChannel.invokeMethod<bool>('stripExifImage', {
        'src': srcPath,
        'dest': destPath,
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  // ---- 系统通知与定时调度 (P2) ----
  @override
  Future<int> showNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    try {
      final res = await _nativeChannel.invokeMethod<int>('showNotification', {
        'title': title,
        'body': body,
        'payload': payload,
      });
      return res ?? -1;
    } catch (_) {
      return -1;
    }
  }

  @override
  Future<int> scheduleNotification({
    required String title,
    required String body,
    required int delaySeconds,
    String? payload,
  }) async {
    try {
      final res =
          await _nativeChannel.invokeMethod<int>('scheduleNotification', {
        'title': title,
        'body': body,
        'delaySeconds': delaySeconds,
        'payload': payload,
      });
      return res ?? -1;
    } catch (_) {
      return -1;
    }
  }

  @override
  Future<bool> cancelNotification(int id) async {
    try {
      final res = await _nativeChannel.invokeMethod<bool>('cancelNotification', {
        'id': id,
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> cancelAllNotifications() async {
    try {
      final res = await _nativeChannel.invokeMethod<bool>('cancelAllNotifications');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  // ---- 音频播放与频率发生器 (P2) ----
  @override
  Future<bool> playAudio(String filePath) async {
    try {
      final res = await _nativeChannel.invokeMethod<bool>('playAudio', {
        'path': filePath,
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> stopAudio() async {
    try {
      final res = await _nativeChannel.invokeMethod<bool>('stopAudio');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> playTone(double frequencyHz, int durationMs) async {
    try {
      final res = await _nativeChannel.invokeMethod<bool>('playTone', {
        'frequency': frequencyHz,
        'durationMs': durationMs,
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  // ---- 生物认证与端侧交互 ----
  @override
  Future<bool> isBiometricsAvailable() async {
    try {
      final res = await _nativeChannel.invokeMethod<bool>('isBiometricsAvailable');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<Map<String, dynamic>> authenticateBiometrics({String? reason}) async {
    try {
      final res = await _nativeChannel.invokeMapMethod<String, dynamic>(
        'authenticateBiometrics',
        {'reason': reason},
      );
      return res ?? {'success': false, 'error': 'failed'};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  // ---- 麦克风录音与声音分贝感知 ----
  @override
  Future<bool> startAudioRecording(String destPath) async {
    try {
      final res = await _nativeChannel.invokeMethod<bool>('startAudioRecording', {
        'path': destPath,
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<Map<String, dynamic>?> stopAudioRecording() async {
    try {
      final res = await _nativeChannel.invokeMapMethod<String, dynamic>('stopAudioRecording');
      return res;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<double> getAudioDecibel() async {
    try {
      final res = await _nativeChannel.invokeMethod<double>('getAudioDecibel');
      return res ?? 0.0;
    } catch (_) {
      return 0.0;
    }
  }

  // ---- 语音合成 (TTS) ----
  @override
  Future<bool> speakText(
    String text, {
    String? language,
    double? pitch,
    double? rate,
  }) async {
    try {
      final res = await _nativeChannel.invokeMethod<bool>('speakText', {
        'text': text,
        'language': language,
        'pitch': pitch,
        'rate': rate,
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> stopSpeaking() async {
    try {
      final res = await _nativeChannel.invokeMethod<bool>('stopSpeaking');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  // ---- 高级交互弹窗 (P3) ----
  @override
  Future<String?> showPrompt({
    required String title,
    String? hint,
    String? defaultValue,
  }) async {
    if (!mounted) return null;
    final controller = TextEditingController(text: defaultValue ?? '');
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  @override
  Future<Map<String, dynamic>?> showPickItem({
    required String title,
    required List<String> items,
    int initialIndex = 0,
  }) async {
    if (!mounted) return null;
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(title),
        children: [
          for (int i = 0; i < items.length; i++)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, {'index': i, 'text': items[i]}),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  items[i],
                  style: TextStyle(
                    fontWeight: i == initialIndex ? FontWeight.bold : FontWeight.normal,
                    color: i == initialIndex ? Theme.of(ctx).colorScheme.primary : null,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Future<Map<String, dynamic>?> showBottomSheet({
    required String title,
    required List<String> items,
  }) async {
    if (!mounted) return null;
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (title.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    title,
                    style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: items.length,
                  itemBuilder: (ctx, idx) {
                    return ListTile(
                      title: Text(items[idx]),
                      onTap: () => Navigator.of(ctx).pop({
                        'index': idx,
                        'text': items[idx],
                      }),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ---- 硬件与系统深度状态感知 (P3) ----
  int _cachedBattery = 100;
  bool _cachedIsCharging = false;
  String _cachedNetType = 'unknown';

  @override
  int get batteryLevel => _cachedBattery;

  @override
  bool get isCharging => _cachedIsCharging;

  @override
  String get networkType => _cachedNetType;

  @override
  Future<int> getBatteryLevel() async {
    try {
      final res = await _nativeChannel.invokeMethod<int>('getBatteryLevel');
      if (res != null) _cachedBattery = res;
      return res ?? _cachedBattery;
    } catch (_) {
      return _cachedBattery;
    }
  }

  @override
  Future<bool> checkIsCharging() async {
    try {
      final res = await _nativeChannel.invokeMethod<bool>('isCharging');
      if (res != null) _cachedIsCharging = res;
      return res ?? _cachedIsCharging;
    } catch (_) {
      return _cachedIsCharging;
    }
  }

  @override
  Future<String> fetchNetworkType() async {
    try {
      final res = await _nativeChannel.invokeMethod<String>('getNetworkType');
      if (res != null) _cachedNetType = res;
      return res ?? _cachedNetType;
    } catch (_) {
      return _cachedNetType;
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
