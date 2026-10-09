import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';
import 'package:plugin_toolbox_lua/plugin_toolbox_lua.dart';
import 'package:plugin_toolbox_dui/plugin_toolbox_dui.dart';
import 'package:plugin_toolbox_ui/plugin_toolbox_ui.dart';

import 'plugin_native_bridge.dart';

/// 动态插件宿主页面容器
class DynamicPluginHostPage extends StatefulWidget {
  final DynamicPlugin plugin;

  const DynamicPluginHostPage({super.key, required this.plugin});

  @override
  State<DynamicPluginHostPage> createState() => _DynamicPluginHostPageState();
}

class _DynamicPluginHostPageState extends State<DynamicPluginHostPage>
    with WidgetsBindingObserver
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
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _nativeBridge = PluginNativeBridge(pluginRootDir: widget.plugin.rootDir);
    _duiState = DuiState();
    _eventHandler = DuiEventHandler(
      state: _duiState,
      executor: this,
      permissionChecker: (perm) => widget.plugin.context?.hasPermission(perm) ?? false,
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

  // --- LuaHostDelegate: UI 弹窗与用户交互 ---
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
  Future<String?> showPrompt({
    required String title,
    String? hint,
    String? defaultValue,
  }) async {
    if (!mounted) return null;
    final controller = TextEditingController(text: defaultValue);
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(hintText: hint),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    return res;
  }

  @override
  Future<Map<String, dynamic>?> showPickItem({
    required String title,
    required List<String> items,
    int initialIndex = 0,
  }) async {
    if (!mounted) return null;
    return await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(title),
        children: items.asMap().entries.map((entry) {
          final idx = entry.key;
          final item = entry.value;
          return SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop({'index': idx, 'text': item}),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(item),
            ),
          );
        }).toList(),
      ),
    );
  }

  @override
  Future<Map<String, dynamic>?> showBottomSheet({
    required String title,
    required List<String> items,
  }) async {
    if (!mounted) return null;
    return await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                title,
                style: Theme.of(ctx).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
            ),
            const Divider(height: 1),
            ...items.asMap().entries.map((entry) {
              final idx = entry.key;
              final item = entry.value;
              return ListTile(
                title: Text(item, textAlign: TextAlign.center),
                onTap: () => Navigator.of(ctx).pop({'index': idx, 'text': item}),
              );
            }),
          ],
        ),
      ),
    );
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

  // --- LuaHostDelegate: 平台与系统能力委派至 PluginNativeBridge ---
  @override
  Future<void> shareText(String text, {String? subject}) =>
      _nativeBridge.shareText(text, subject: subject);

  @override
  Future<bool> openUrl(String url) => _nativeBridge.openUrl(url);

  @override
  Future<String?> pickFile({List<String>? allowedExtensions}) =>
      _nativeBridge.pickFile(allowedExtensions: allowedExtensions);

  @override
  Future<String?> pickImage() => _nativeBridge.pickImage();

  @override
  Future<bool> setTorch(bool enabled) => _nativeBridge.setTorch(enabled);

  @override
  bool get isTorchOn => _nativeBridge.isTorchOn;

  @override
  Future<bool> shareFile(String filePath, {String? mimeType, String? subject}) =>
      _nativeBridge.shareFile(filePath, mimeType: mimeType, subject: subject);

  @override
  Future<bool> saveToGallery(String filePath) =>
      _nativeBridge.saveToGallery(filePath);

  @override
  Future<bool> exportFile(String filePath, {String? defaultName}) =>
      _nativeBridge.exportFile(filePath, defaultName: defaultName);

  @override
  Future<String?> scanBarcode({String? prompt}) async {
    final res = await _nativeBridge.scanBarcode(prompt: prompt);
    if (res != null) return res;
    if (!mounted) return null;
    if (!Platform.isAndroid && !Platform.isIOS) {
      return await showPrompt(
        title: prompt ?? '扫码识别 (桌面模拟)',
        hint: '请输入或粘贴条形码/二维码扫描内容',
      );
    }
    return null;
  }

  @override
  Future<String?> decodeBarcodeFromImage(String filePath) async {
    final res = await _nativeBridge.decodeBarcodeFromImage(filePath);
    if (res != null) return res;
    if (!mounted) return null;
    if (!Platform.isAndroid && !Platform.isIOS) {
      return await showPrompt(
        title: '图片二维码识别 (桌面模拟)',
        hint: '未检测到原生条码识别器，可手动输入模拟识别结果',
      );
    }
    return null;
  }

  @override
  Future<bool> startSensor(String type) => _nativeBridge.startSensor(type);

  @override
  Future<bool> stopSensor(String type) => _nativeBridge.stopSensor(type);

  @override
  Future<Map<String, dynamic>?> getSensorData(String type) =>
      _nativeBridge.getSensorData(type);

  @override
  Future<Map<String, dynamic>?> imageInfo(String filePath) =>
      _nativeBridge.imageInfo(filePath);

  @override
  Future<bool> compressImage(String srcPath, String destPath, {int quality = 80}) =>
      _nativeBridge.compressImage(srcPath, destPath, quality: quality);

  @override
  Future<bool> cropImage(String srcPath, String destPath,
          {required int x, required int y, required int width, required int height}) =>
      _nativeBridge.cropImage(srcPath, destPath,
          x: x, y: y, width: width, height: height);

  @override
  Future<bool> convertImage(String srcPath, String destPath, {required String format}) =>
      _nativeBridge.convertImage(srcPath, destPath, format: format);

  @override
  Future<bool> stripExifImage(String srcPath, String destPath) =>
      _nativeBridge.stripExifImage(srcPath, destPath);

  @override
  Future<int> showNotification({required String title, required String body, String? payload}) =>
      _nativeBridge.showNotification(title: title, body: body, payload: payload);

  @override
  Future<int> scheduleNotification(
          {required String title, required String body, required int delaySeconds, String? payload}) =>
      _nativeBridge.scheduleNotification(
          title: title, body: body, delaySeconds: delaySeconds, payload: payload);

  @override
  Future<bool> cancelNotification(int id) =>
      _nativeBridge.cancelNotification(id);

  @override
  Future<bool> cancelAllNotifications() =>
      _nativeBridge.cancelAllNotifications();

  @override
  Future<bool> playAudio(String filePath) => _nativeBridge.playAudio(filePath);

  @override
  Future<bool> stopAudio() => _nativeBridge.stopAudio();

  @override
  Future<bool> playTone(double frequencyHz, int durationMs) =>
      _nativeBridge.playTone(frequencyHz, durationMs);

  @override
  Future<bool> startAudioRecording(String destPath) =>
      _nativeBridge.startAudioRecording(destPath);

  @override
  Future<Map<String, dynamic>?> stopAudioRecording() =>
      _nativeBridge.stopAudioRecording();

  @override
  Future<double> getAudioDecibel() => _nativeBridge.getAudioDecibel();

  @override
  Future<bool> speakText(String text, {String? language, double? pitch, double? rate}) =>
      _nativeBridge.speakText(text, language: language, pitch: pitch, rate: rate);

  @override
  Future<bool> stopSpeaking() => _nativeBridge.stopSpeaking();

  @override
  Future<bool> setKeepScreenOn(bool enabled) =>
      _nativeBridge.setKeepScreenOn(enabled);

  @override
  Future<bool> setBrightness(double brightness) =>
      _nativeBridge.setBrightness(brightness);

  @override
  Future<double> getBrightness() => _nativeBridge.getBrightness();

  @override
  Future<bool> resetBrightness() => _nativeBridge.resetBrightness();

  @override
  int get batteryLevel => 100;

  @override
  bool get isCharging => false;

  @override
  Future<bool> checkIsCharging() async => false;

  @override
  String get networkType => 'unknown';

  @override
  Future<int> getBatteryLevel() => _nativeBridge.getBatteryLevel();

  @override
  Future<String> fetchNetworkType() => _nativeBridge.fetchNetworkType();

  @override
  Future<Map<String, dynamic>?> getInitialShare() =>
      _nativeBridge.getInitialShare();

  @override
  Future<bool> isBiometricsAvailable() =>
      _nativeBridge.isBiometricsAvailable();

  @override
  Future<Map<String, dynamic>> authenticateBiometrics({String? reason}) =>
      _nativeBridge.authenticateBiometrics(reason: reason);

  @override
  Future<bool> isLocationAvailable() => _nativeBridge.isLocationAvailable();

  @override
  Future<Map<String, dynamic>?> getCurrentPosition() =>
      _nativeBridge.getCurrentPosition();

  @override
  Future<bool> isNfcAvailable() => _nativeBridge.isNfcAvailable();

  @override
  Future<Map<String, dynamic>?> readNdef() => _nativeBridge.readNdef();

  @override
  Future<bool> writeNdef(List<Map<String, dynamic>> records) =>
      _nativeBridge.writeNdef(records);

  @override
  Future<bool> isBluetoothAvailable() =>
      _nativeBridge.isBluetoothAvailable();

  @override
  Future<bool> startBluetoothScan(
          void Function(Map<String, dynamic> device) onDeviceFound) =>
      _nativeBridge.startBluetoothScan(onDeviceFound);

  @override
  Future<bool> stopBluetoothScan() => _nativeBridge.stopBluetoothScan();

  @override
  Future<bool> connectBluetooth(String deviceId) =>
      _nativeBridge.connectBluetooth(deviceId);

  @override
  Future<bool> disconnectBluetooth(String deviceId) =>
      _nativeBridge.disconnectBluetooth(deviceId);

  @override
  Future<String?> readBluetoothCharacteristic(
          String deviceId, String serviceUuid, String charUuid) =>
      _nativeBridge.readBluetoothCharacteristic(deviceId, serviceUuid, charUuid);

  @override
  Future<bool> writeBluetoothCharacteristic(
          String deviceId, String serviceUuid, String charUuid, String value) =>
      _nativeBridge.writeBluetoothCharacteristic(deviceId, serviceUuid, charUuid, value);

  @override
  Future<Map<String, dynamic>?> recognizeText(String filePath) =>
      _nativeBridge.recognizeText(filePath);

  @override
  Future<bool> isAiAvailable() => _nativeBridge.isAiAvailable();

  @override
  Future<Map<String, dynamic>> aiChat({
    required List<Map<String, dynamic>> messages,
    String? model,
    double? temperature,
  }) =>
      _nativeBridge.aiChat(
          messages: messages, model: model, temperature: temperature);

  @override
  Stream<String> aiStreamChat({
    required List<Map<String, dynamic>> messages,
    String? model,
    double? temperature,
  }) =>
      _nativeBridge.aiStreamChat(
          messages: messages, model: model, temperature: temperature);

  @override
  Widget build(BuildContext context) {
    return PluginPageScaffold(
      title: widget.plugin.name,
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
