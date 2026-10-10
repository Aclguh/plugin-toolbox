import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';
import 'package:plugin_toolbox_lua/plugin_toolbox_lua.dart';

class MockLuaHostDelegate implements LuaHostDelegate {
  final Map<String, dynamic> state = {};
  final List<String> toasts = [];
  final List<String> haptics = [];
  bool keyboardHidden = false;
  String? sharedText;
  String? openedUrl;
  String? pickedFileResult;
  String? pickedImageResult;

  @override
  void onStateChanged(String key, dynamic value) {
    state[key] = value;
  }

  @override
  dynamic getState(String key) => state[key];

  @override
  Map<String, dynamic> getAllStates() => Map.unmodifiable(state);

  @override
  void showToast(String message) {
    toasts.add(message);
  }

  @override
  Future<void> showAlert(String title, String message) async {}

  @override
  Future<bool> showConfirm(String title, String message) async => true;

  @override
  void hideKeyboard() {
    keyboardHidden = true;
  }

  @override
  void hapticFeedback(String type) {
    haptics.add(type);
  }

  @override
  Future<void> shareText(String text, {String? subject}) async {
    sharedText = text;
  }

  @override
  Future<bool> openUrl(String url) async {
    openedUrl = url;
    return true;
  }

  @override
  Future<String?> pickFile({List<String>? allowedExtensions}) async =>
      pickedFileResult;

  @override
  Future<String?> pickImage() async => pickedImageResult;

  bool torchState = false;
  String? sharedFilePath;
  String? sharedFileMimeType;
  String? sharedFileSubject;
  String? savedGalleryPath;
  String? exportedFilePath;
  String? exportedFileDefaultName;
  String? mockPickedDate = '2025-06-15';
  String? mockPickedTime = '15:45';

  @override
  Future<bool> setTorch(bool enabled) async {
    torchState = enabled;
    return true;
  }

  @override
  bool get isTorchOn => torchState;

  @override
  Future<bool> shareFile(
    String filePath, {
    String? mimeType,
    String? subject,
  }) async {
    sharedFilePath = filePath;
    sharedFileMimeType = mimeType;
    sharedFileSubject = subject;
    return true;
  }

  @override
  Future<bool> saveToGallery(String filePath) async {
    savedGalleryPath = filePath;
    return true;
  }

  @override
  Future<bool> exportFile(
    String filePath, {
    String? defaultName,
  }) async {
    exportedFilePath = filePath;
    exportedFileDefaultName = defaultName;
    return true;
  }

  @override
  Future<String?> pickDate({
    String? initialDate,
    String? firstDate,
    String? lastDate,
  }) async =>
      mockPickedDate;

  @override
  Future<String?> pickTime({
    String? initialTime,
  }) async =>
      mockPickedTime;

  String? mockScannedCode = 'https://example.com/mock-qr';
  String? mockDecodedCode = 'mock-decoded-barcode-123';
  final Map<String, Map<String, dynamic>> mockSensors = {
    'accelerometer': {'x': 1.0, 'y': 2.0, 'z': 9.8},
    'gyroscope': {'x': 0.1, 'y': 0.2, 'z': 0.3},
    'compass': {'heading': 180.0},
  };
  final List<String> startedSensors = [];
  final List<String> stoppedSensors = [];

  @override
  Future<String?> scanBarcode({String? prompt}) async => mockScannedCode;

  @override
  Future<String?> decodeBarcodeFromImage(String filePath) async => mockDecodedCode;

  @override
  Future<bool> startSensor(String type) async {
    startedSensors.add(type);
    return true;
  }

  @override
  Future<bool> stopSensor(String type) async {
    stoppedSensors.add(type);
    return true;
  }

  @override
  Future<Map<String, dynamic>?> getSensorData(String type) async =>
      mockSensors[type];

  // P2 Mock implementations
  final Map<String, dynamic> mockImageInfo = {
    'width': 800,
    'height': 600,
    'format': 'image/jpeg',
    'size': 102400,
  };
  String? compressedSrc;
  String? compressedDest;
  int? compressedQuality;
  String? croppedSrc;
  String? croppedDest;
  String? convertedSrc;
  String? convertedDest;
  String? convertedFormat;
  String? stripExifSrc;
  String? stripExifDest;

  @override
  Future<Map<String, dynamic>?> imageInfo(String filePath) async =>
      mockImageInfo;

  @override
  Future<bool> compressImage(
    String srcPath,
    String destPath, {
    int quality = 80,
  }) async {
    compressedSrc = srcPath;
    compressedDest = destPath;
    compressedQuality = quality;
    return true;
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
    croppedSrc = srcPath;
    croppedDest = destPath;
    return true;
  }

  @override
  Future<bool> convertImage(
    String srcPath,
    String destPath, {
    required String format,
  }) async {
    convertedSrc = srcPath;
    convertedDest = destPath;
    convertedFormat = format;
    return true;
  }

  @override
  Future<bool> stripExifImage(String srcPath, String destPath) async {
    stripExifSrc = srcPath;
    stripExifDest = destPath;
    return true;
  }

  final List<Map<String, dynamic>> sentNotifications = [];
  final List<int> cancelledNotificationIds = [];
  bool cancelledAllNotifs = false;
  int notifIdCounter = 100;

  @override
  Future<int> showNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    final id = ++notifIdCounter;
    sentNotifications
        .add({'id': id, 'title': title, 'body': body, 'payload': payload});
    return id;
  }

  @override
  Future<int> scheduleNotification({
    required String title,
    required String body,
    required int delaySeconds,
    String? payload,
  }) async {
    final id = ++notifIdCounter;
    sentNotifications.add({
      'id': id,
      'title': title,
      'body': body,
      'delaySeconds': delaySeconds,
      'payload': payload,
    });
    return id;
  }

  @override
  Future<bool> cancelNotification(int id) async {
    cancelledNotificationIds.add(id);
    return true;
  }

  @override
  Future<bool> cancelAllNotifications() async {
    cancelledAllNotifs = true;
    return true;
  }

  String? playedAudioPath;
  bool audioStopped = false;
  double? playedToneFreq;
  int? playedToneDuration;

  @override
  Future<bool> playAudio(String filePath) async {
    playedAudioPath = filePath;
    return true;
  }

  @override
  Future<bool> stopAudio() async {
    audioStopped = true;
    return true;
  }

  @override
  Future<bool> playTone(double frequencyHz, int durationMs) async {
    playedToneFreq = frequencyHz;
    playedToneDuration = durationMs;
    return true;
  }

  // P3 Mock implementations
  String? mockPromptResult = 'user-inputted-text';
  Map<String, dynamic>? mockPickItemResult = {'index': 1, 'text': 'Option 2'};

  @override
  Future<String?> showPrompt({
    required String title,
    String? hint,
    String? defaultValue,
  }) async =>
      mockPromptResult;

  @override
  Future<Map<String, dynamic>?> showPickItem({
    required String title,
    required List<String> items,
    int initialIndex = 0,
  }) async =>
      mockPickItemResult;

  Map<String, dynamic>? mockBottomSheetResult = {'index': 0, 'text': 'Item 1'};

  @override
  Future<Map<String, dynamic>?> showBottomSheet({
    required String title,
    required List<String> items,
  }) async =>
      mockBottomSheetResult;

  int mockBatteryLevel = 85;
  bool mockIsCharging = true;
  String mockNetworkType = 'wifi';

  @override
  int get batteryLevel => mockBatteryLevel;

  @override
  bool get isCharging => mockIsCharging;

  @override
  String get networkType => mockNetworkType;

  @override
  Future<int> getBatteryLevel() async => mockBatteryLevel;

  @override
  Future<bool> checkIsCharging() async => mockIsCharging;

  @override
  Future<String> fetchNetworkType() async => mockNetworkType;

  bool mockBiometricsAvailable = true;
  Map<String, dynamic> mockBiometricsAuth = {'success': true};
  String? recordedAudioPath;
  bool audioRecordingStopped = false;
  double mockDecibel = 65.5;
  String? spokenText;
  String? spokenLanguage;
  double? spokenPitch;
  double? spokenRate;
  bool speechStopped = false;

  @override
  Future<bool> isBiometricsAvailable() async => mockBiometricsAvailable;

  @override
  Future<Map<String, dynamic>> authenticateBiometrics({String? reason}) async =>
      mockBiometricsAuth;

  @override
  Future<bool> startAudioRecording(String destPath) async {
    recordedAudioPath = destPath;
    return true;
  }

  @override
  Future<Map<String, dynamic>?> stopAudioRecording() async {
    audioRecordingStopped = true;
    return {
      'path': recordedAudioPath ?? 'data/rec.m4a',
      'durationMs': 1500,
      'size': 12345,
    };
  }

  @override
  Future<double> getAudioDecibel() async => mockDecibel;

  @override
  Future<bool> speakText(
    String text, {
    String? language,
    double? pitch,
    double? rate,
  }) async {
    spokenText = text;
    spokenLanguage = language;
    spokenPitch = pitch;
    spokenRate = rate;
    return true;
  }

  @override
  Future<bool> stopSpeaking() async {
    speechStopped = true;
    return true;
  }

  bool keepScreenOn = false;
  double screenBrightness = 1.0;
  bool brightnessReset = false;
  Map<String, dynamic>? initialShareData = {
    'type': 'text',
    'text': 'shared content'
  };
  bool locationAvailable = true;
  Map<String, dynamic>? mockLocation = {
    'latitude': 31.2304,
    'longitude': 121.4737,
    'altitude': 15.5,
    'accuracy': 5.0,
    'timestamp': 1700000000,
  };
  bool nfcAvailable = true;
  Map<String, dynamic>? mockNdefRead = {
    'records': [
      {'type': 'text', 'payload': 'Hello NFC'}
    ]
  };
  List<Map<String, dynamic>> writtenNdefRecords = [];
  bool bluetoothAvailable = true;
  bool bluetoothScanning = false;
  String? connectedBleDevice;
  String? disconnectedBleDevice;
  String? mockBleCharValue = '01020304';
  String? writtenBleCharValue;
  Map<String, dynamic>? mockOcrResult = {
    'text': 'Recognized Sample Text',
    'lines': ['Recognized', 'Sample Text'],
  };
  bool aiAvailable = true;
  Map<String, dynamic> mockAiChatResponse = {
    'ok': true,
    'text': 'AI generated response',
    'usage': {'totalTokens': 42},
  };
  String? openedPluginId;
  Map<String, dynamic>? openedPluginData;

  @override
  Future<bool> setKeepScreenOn(bool enabled) async {
    keepScreenOn = enabled;
    return true;
  }

  @override
  Future<bool> setBrightness(double brightness) async {
    screenBrightness = brightness;
    return true;
  }

  @override
  Future<double> getBrightness() async => screenBrightness;

  @override
  Future<bool> resetBrightness() async {
    brightnessReset = true;
    screenBrightness = 1.0;
    return true;
  }

  @override
  Future<Map<String, dynamic>?> getInitialShare() async => initialShareData;

  @override
  Future<bool> isLocationAvailable() async => locationAvailable;

  @override
  Future<Map<String, dynamic>?> getCurrentPosition() async => mockLocation;

  @override
  Future<bool> isNfcAvailable() async => nfcAvailable;

  @override
  Future<Map<String, dynamic>?> readNdef() async => mockNdefRead;

  @override
  Future<bool> writeNdef(List<Map<String, dynamic>> records) async {
    writtenNdefRecords = records;
    return true;
  }

  @override
  Future<bool> isBluetoothAvailable() async => bluetoothAvailable;

  @override
  Future<bool> startBluetoothScan(
      void Function(Map<String, dynamic> device) onDeviceFound) async {
    bluetoothScanning = true;
    onDeviceFound(
        {'id': 'AA:BB:CC:DD:EE:FF', 'name': 'Test Beacon', 'rssi': -55});
    return true;
  }

  @override
  Future<bool> stopBluetoothScan() async {
    bluetoothScanning = false;
    return true;
  }

  @override
  Future<bool> connectBluetooth(String deviceId) async {
    connectedBleDevice = deviceId;
    return true;
  }

  @override
  Future<bool> disconnectBluetooth(String deviceId) async {
    disconnectedBleDevice = deviceId;
    return true;
  }

  @override
  Future<String?> readBluetoothCharacteristic(
          String deviceId, String serviceUuid, String charUuid) async =>
      mockBleCharValue;

  @override
  Future<bool> writeBluetoothCharacteristic(
    String deviceId,
    String serviceUuid,
    String charUuid,
    String value,
  ) async {
    writtenBleCharValue = value;
    return true;
  }

  @override
  Future<Map<String, dynamic>?> recognizeText(String filePath) async =>
      mockOcrResult;

  @override
  Future<bool> isAiAvailable() async => aiAvailable;

  @override
  Future<Map<String, dynamic>> aiChat({
    required List<Map<String, dynamic>> messages,
    String? model,
    double? temperature,
  }) async =>
      mockAiChatResponse;

  @override
  Stream<String> aiStreamChat({
    required List<Map<String, dynamic>> messages,
    String? model,
    double? temperature,
  }) async* {
    yield 'Chunk1 ';
    yield 'Chunk2';
  }

  @override
  Future<bool> openPlugin(String targetPluginId,
      {Map<String, dynamic>? initialData}) async {
    openedPluginId = targetPluginId;
    openedPluginData = initialData;
    return true;
  }
}

class InMemoryPluginStorage implements PluginStorage {
  final Map<String, dynamic> _data = {};

  @override
  Future<String?> getString(String key) async => _data[key] as String?;

  @override
  Future<bool> setString(String key, String value) async {
    _data[key] = value;
    return true;
  }

  @override
  Future<bool?> getBool(String key) async => _data[key] as bool?;

  @override
  Future<bool> setBool(String key, bool value) async {
    _data[key] = value;
    return true;
  }

  @override
  Future<int?> getInt(String key) async => _data[key] as int?;

  @override
  Future<bool> setInt(String key, int value) async {
    _data[key] = value;
    return true;
  }

  @override
  Future<double?> getDouble(String key) async => _data[key] as double?;

  @override
  Future<bool> setDouble(String key, double value) async {
    _data[key] = value;
    return true;
  }

  @override
  Future<List<String>?> getStringList(String key) async => _data[key] as List<String>?;

  @override
  Future<bool> setStringList(String key, List<String> value) async {
    _data[key] = value;
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    _data.remove(key);
    return true;
  }

  @override
  Future<bool> clear() async {
    _data.clear();
    return true;
  }
}

void main() {
  group('LuaEngine & Host APIs', () {
    late MockLuaHostDelegate delegate;
    late PluginContext context;
    late LuaEngine engine;

    setUp(() {
      delegate = MockLuaHostDelegate();
      context = PluginContext(
        pluginId: 'test_plugin',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {PluginPermission.clipboard, PluginPermission.storage},
      );
      engine = LuaEngine(context: context, delegate: delegate);
    });

    tearDown(() {
      engine.close();
    });

    test('state get and set from Lua', () {
      engine.loadAndExecute('''
        state.set("message", "Hello Lua")
        val = state.get("message")
      ''');

      expect(delegate.getState('message'), 'Hello Lua');
    });

    test('codec 与 hash 宿主 API 以全局表形式绑定注入 (仅验证绑定, 不验证业务结果)', () {
      engine.loadAndExecute('''
        state.set("codec_type", type(codec))
        state.set("codec_encode_fn", type(codec.base64Encode))
        state.set("codec_decode_fn", type(codec.base64Decode))
        state.set("codec_url_fn", type(codec.urlEncode))
        state.set("hash_type", type(hash))
        state.set("hash_md5_fn", type(hash.md5))
        state.set("hash_sha1_fn", type(hash.sha1))
        state.set("hash_sha256_fn", type(hash.sha256))
      ''');

      expect(delegate.getState('codec_type'), 'table');
      expect(delegate.getState('codec_encode_fn'), 'function');
      expect(delegate.getState('codec_decode_fn'), 'function');
      expect(delegate.getState('codec_url_fn'), 'function');
      expect(delegate.getState('hash_type'), 'table');
      expect(delegate.getState('hash_md5_fn'), 'function');
      expect(delegate.getState('hash_sha1_fn'), 'function');
      expect(delegate.getState('hash_sha256_fn'), 'function');
    });

    test('宿主 API 参数类型错误被隔离为 Lua 执行错误 (不逃逸宿主)', () {
      expect(
        () => engine.loadAndExecute('codec.base64Encode(nil)'),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('Lua 执行错误'),
        )),
      );
    });

    test('system 宿主 API 以全局表形式绑定注入 (仅验证绑定, 不验证设备相关取值)', () {
      engine.loadAndExecute('''
        state.set("system_type", type(system))
        state.set("system_platform_fn", type(system.platform))
        state.set("system_os_version_fn", type(system.osVersion))
        state.set("system_hostname_fn", type(system.hostname))
        state.set("system_cores_fn", type(system.cores))
        state.set("system_locale_fn", type(system.locale))
        state.set("system_screen_w_fn", type(system.screenWidth))
        state.set("system_screen_h_fn", type(system.screenHeight))
        state.set("system_pixel_ratio_fn", type(system.pixelRatio))
        state.set("system_brightness_fn", type(system.brightness))
      ''');

      expect(delegate.getState('system_type'), 'table');
      expect(delegate.getState('system_platform_fn'), 'function');
      expect(delegate.getState('system_os_version_fn'), 'function');
      expect(delegate.getState('system_hostname_fn'), 'function');
      expect(delegate.getState('system_cores_fn'), 'function');
      expect(delegate.getState('system_locale_fn'), 'function');
      expect(delegate.getState('system_screen_w_fn'), 'function');
      expect(delegate.getState('system_screen_h_fn'), 'function');
      expect(delegate.getState('system_pixel_ratio_fn'), 'function');
      expect(delegate.getState('system_brightness_fn'), 'function');
    });

    test('callFunction invokes Lua functions', () {
      engine.loadAndExecute('''
        function add(a, b)
          return a + b
        end
      ''');

      final result = engine.callFunction('add', [10, 25]);
      expect(result, 35);
    });
  });

  group('Lua 沙箱安全与执行防护', () {
    late MockLuaHostDelegate delegate;
    late PluginContext context;
    late LuaEngine engine;

    setUp(() {
      delegate = MockLuaHostDelegate();
      context = PluginContext(
        pluginId: 'test_plugin',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {PluginPermission.clipboard, PluginPermission.storage},
      );
      engine = LuaEngine(context: context, delegate: delegate);
    });

    tearDown(() {
      engine.close();
    });

    test('危险标准库全局全部被置空', () {
      engine.loadAndExecute('''
        state.set("os_type", type(os))
        state.set("io_type", type(io))
        state.set("debug_type", type(debug))
        state.set("package_type", type(package))
        state.set("require_type", type(require))
        state.set("dofile_type", type(dofile))
        state.set("loadfile_type", type(loadfile))
      ''');

      expect(delegate.getState('os_type'), 'nil');
      expect(delegate.getState('io_type'), 'nil');
      expect(delegate.getState('debug_type'), 'nil');
      expect(delegate.getState('package_type'), 'nil');
      expect(delegate.getState('require_type'), 'nil');
      expect(delegate.getState('dofile_type'), 'nil');
      expect(delegate.getState('loadfile_type'), 'nil');
    });

    test('安全基础库 (table/string/math) 保持可用', () {
      engine.loadAndExecute('''
        local t = {3, 1, 2}
        table.sort(t)
        state.set("first", tostring(t[1]))
        state.set("upper", string.upper("abc"))
        state.set("abs", tostring(math.abs(-5)))
      ''');

      expect(delegate.getState('first'), '1');
      expect(delegate.getState('upper'), 'ABC');
      expect(delegate.getState('abs'), '5');
    });

    test('os.execute 不可调用并降级为执行错误', () {
      expect(
        () => engine.loadAndExecute('os.execute("echo pwned")'),
        throwsException,
      );
    });

    test('loadfile 不可调用并降级为执行错误', () {
      expect(
        () => engine.loadAndExecute('loadfile("/etc/passwd")'),
        throwsException,
      );
    });

    test('指令数预算阻断死循环', () {
      final limited = LuaEngine(
        context: context,
        delegate: delegate,
        instructionBudget: 5000,
      );
      try {
        expect(
          () => limited.loadAndExecute('while true do end'),
          throwsA(isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Lua 执行错误'),
          )),
        );
      } finally {
        limited.close();
      }
    });

    test('包含循环引用的集合压栈被拒绝', () {
      engine.loadAndExecute('function sink(v) return 1 end');
      final cyclic = <String, dynamic>{'k': 'v'};
      cyclic['self'] = cyclic;
      expect(() => engine.callFunction('sink', [cyclic]), throwsException);
    });

    test('Lua 侧包含循环引用的表出栈被安全截断，不发生栈溢出', () {
      engine.loadAndExecute('''
        function getCyclic()
          local a = { name = "root" }
          a.self = a
          return a
        end
      ''');
      final res = engine.callFunction('getCyclic');
      expect(res, isA<Map>());
      expect((res as Map)['name'], 'root');
      expect(res['self'], isNull);
    });
  });

  group('Lua 异步宿主 API', () {
    late MockLuaHostDelegate delegate;
    late PluginContext context;
    late LuaEngine engine;

    setUp(() {
      delegate = MockLuaHostDelegate();
      context = PluginContext(
        pluginId: 'test_plugin',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {PluginPermission.clipboard, PluginPermission.storage},
      );
      engine = LuaEngine(context: context, delegate: delegate);
    });

    tearDown(() {
      engine.close();
    });

    test('clipboard.get 通过回调异步返回剪贴板文本', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      const channel = SystemChannels.platform;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'Clipboard.getData') {
          return <String, dynamic>{'text': 'mock-clipboard-text'};
        }
        return null;
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding.instance
          .defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null));

      engine.loadAndExecute('''
        clipboard.get(function(val) state.set("clip_value", val) end)
      ''');

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(delegate.getState('clip_value'), 'mock-clipboard-text');
    });

    test('storage.get 通过回调返回已存储的值', () async {
      engine.loadAndExecute('''
        storage.set("k1", "v1")
        storage.get("k1", function(val) state.set("got", val) end)
      ''');

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(delegate.getState('got'), 'v1');
    });

    test('storage.remove 删除后 get 回调收到 nil', () async {
      engine.loadAndExecute('''
        storage.set("k2", "v2")
        storage.remove("k2")
        storage.get("k2", function(val) state.set("got_nil", val == nil) end)
      ''');

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(delegate.getState('got_nil'), true);
    });

    test('dialog.confirm 异步携带用户选择回调', () async {
      engine.loadAndExecute('''
        dialog.confirm("标题", "内容", function(ok) state.set("confirmed", ok) end)
      ''');

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(delegate.getState('confirmed'), true);
    });

    test('dialog.pickDate 与 dialog.pickTime 支持回调与状态写入', () async {
      engine.loadAndExecute('''
        dialog.pickDate(function(d)
          state.set("cb_date", d)
        end)
        dialog.pickTime(function(t)
          state.set("cb_time", t)
        end)
        dialog.pickDate("2024-01-01")
        dialog.pickTime("12:00")
      ''');

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(delegate.getState('cb_date'), '2025-06-15');
      expect(delegate.getState('cb_time'), '15:45');
      expect(delegate.getState('__dialog_date'), '2025-06-15');
      expect(delegate.getState('__dialog_time'), '15:45');
    });

    test('未声明 network 权限时 network.get 直接报错', () {
      expect(
        () => engine.loadAndExecute('network.get("http://example.com")'),
        throwsException,
      );
    });

    test('Lua 表连续整数索引被识别为 List 数组 (P2-2)', () {
      engine.loadAndExecute('''
        function get_array()
          return {10, 20, 30}
        end
        function get_nested_array()
          return { {1, 2}, {3, 4} }
        end
        function get_map()
          return { a = 1, b = 2 }
        end
        function get_sparse()
          return { [1] = "first", [3] = "third" }
        end
      ''');

      final arrayResult = engine.callFunction('get_array');
      expect(arrayResult, isA<List>());
      expect(arrayResult, [10, 20, 30]);

      final nestedResult = engine.callFunction('get_nested_array');
      expect(nestedResult, isA<List>());
      expect(nestedResult, [
        [1, 2],
        [3, 4],
      ]);

      final mapResult = engine.callFunction('get_map');
      expect(mapResult, isA<Map>());
      expect(mapResult, {'a': 1, 'b': 2});

      // 稀疏表（非连续 1..N）降级为 Map
      final sparseResult = engine.callFunction('get_sparse');
      expect(sparseResult, isA<Map>());
      expect(sparseResult, {'1': 'first', '3': 'third'});
    });

    test('LuaEngine.close() 幂等且禁止在关闭后继续调用 (P2-5)', () {
      expect(engine.isClosed, isFalse);
      engine.close();
      expect(engine.isClosed, isTrue);

      // 再次调用 close 幂等不崩溃
      expect(() => engine.close(), returnsNormally);

      // 关闭后调用执行方法抛出 StateError
      expect(
        () => engine.loadAndExecute('print("hello")'),
        throwsA(isA<StateError>()),
      );
      expect(
        () => engine.callFunction('non_existent'),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('JSON 宿主 API', () {
    late MockLuaHostDelegate delegate;
    late PluginContext context;
    late LuaEngine engine;

    setUp(() {
      delegate = MockLuaHostDelegate();
      context = PluginContext(
        pluginId: 'test_plugin',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {PluginPermission.clipboard, PluginPermission.storage},
      );
      engine = LuaEngine(context: context, delegate: delegate);
    });

    tearDown(() {
      engine.close();
    });

    test('json 全局表以绑定形式注入 (仅验证绑定, 不验证业务数据)', () {
      engine.loadAndExecute('''
        state.set("json_type", type(json))
        state.set("json_encode_fn", type(json.encode))
        state.set("json_decode_fn", type(json.decode))
      ''');

      expect(delegate.getState('json_type'), 'table');
      expect(delegate.getState('json_encode_fn'), 'function');
      expect(delegate.getState('json_decode_fn'), 'function');
    });

    test('json.encode 将 Lua 表结构序列化为 JSON 字符串', () {
      engine.loadAndExecute('''
        function enc()
          return json.encode({
            hello = "world",
            n = 3,
            arr = {1, 2, 3},
            flag = true,
            nested = { inner = {1, 2} },
          })
        end
      ''');

      final out = engine.callFunction('enc') as String;
      final parsed = jsonDecode(out) as Map<String, dynamic>;
      expect(parsed['hello'], 'world');
      expect(parsed['n'], 3);
      expect(parsed['arr'], [1, 2, 3]);
      expect(parsed['flag'], true);
      expect(parsed['nested'], {'inner': [1, 2]});
    });

    test('json.encode 标量与空表', () {
      engine.loadAndExecute('''
        function enc_scalar()
          return json.encode(42)
        end
        function enc_str()
          return json.encode("hi")
        end
        function enc_empty()
          return json.encode({})
        end
      ''');

      expect(engine.callFunction('enc_scalar'), '42');
      expect(engine.callFunction('enc_str'), '"hi"');
      // 空表无 1..N 数组特征, 统一按对象序列化
      expect(engine.callFunction('enc_empty'), '{}');
    });

    test('json.decode 将 JSON 文本还原为 Lua 表结构', () {
      engine.loadAndExecute('''
        function dec(s)
          return json.decode(s)
        end
      ''');

      // null 值依 Lua 表语义表现为键缺失 (赋 nil 即删除键)
      final obj = engine.callFunction('dec',
          ['{"a":[1,2,{"b":null}],"s":"x","f":1.5,"ok":true}']);
      expect(obj, {
        'a': [1, 2, {}],
        's': 'x',
        'f': 1.5,
        'ok': true,
      });
      expect(engine.callFunction('dec', ['[10,20]']), [10, 20]);
      expect(engine.callFunction('dec', ['null']), isNull);
    });

    test('json.decode 后再 encode 与压缩输入保持结构等价', () {
      engine.loadAndExecute('''
        function roundtrip(s)
          return json.encode(json.decode(s))
        end
      ''');

      expect(
        engine.callFunction('roundtrip', ['{ "a" : [1, 2], "b" : "x" }']),
        '{"a":[1,2],"b":"x"}',
      );
    });

    test('json.encode 循环引用表降级为 Lua 执行错误 (不逃逸宿主)', () {
      engine.loadAndExecute('''
        function makeCyclic()
          local t = {}
          t.self = t
          return json.encode(t)
        end
      ''');

      expect(
        () => engine.callFunction('makeCyclic'),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('循环引用'),
        )),
      );
    });

    test('json.encode 不可序列化类型与 json.decode 非法输入均被 pcall 隔离', () {
      engine.loadAndExecute('''
        function tryEncodeFn()
          local ok, err = pcall(json.encode, {f = print})
          state.set("enc_ok", ok)
        end
        function tryDecodeBad()
          local ok, err = pcall(json.decode, "{bad json")
          state.set("dec_ok", ok)
        end
      ''');

      engine.callFunction('tryEncodeFn');
      expect(delegate.getState('enc_ok'), false);
      engine.callFunction('tryDecodeBad');
      expect(delegate.getState('dec_ok'), false);
    });

    test('超深嵌套 JSON 在解析前被深度预检拦截', () {
      final deep = ('[' * 100) + (']' * 100);
      engine.loadAndExecute('''
        function tryDeep(s)
          local ok = pcall(json.decode, s)
          state.set("deep_ok", ok)
        end
      ''');

      engine.callFunction('tryDeep', [deep]);
      expect(delegate.getState('deep_ok'), false);
    });

    test('未声明 network 权限时 network.post 直接报错', () {
      expect(
        () => engine.loadAndExecute('network.post("http://example.com", "{}")'),
        throwsException,
      );
    });

    test('network.post 以绑定形式注入 (仅验证绑定)', () {
      engine.loadAndExecute('state.set("post_fn", type(network.post))');
      expect(delegate.getState('post_fn'), 'function');
    });

    test('HapticApi 触觉反馈调用委派给宿主', () {
      engine.loadAndExecute('''
        haptic.light()
        haptic.medium()
        haptic.heavy()
        haptic.selection()
        haptic.vibrate()
      ''');
      expect(delegate.haptics, ['light', 'medium', 'heavy', 'selection', 'vibrate']);
    });

    test('UiApi 软键盘收起与 Toast 委派给宿主', () {
      engine.loadAndExecute('''
        ui.hideKeyboard()
        ui.toast("测试提示")
      ''');
      expect(delegate.keyboardHidden, true);
      expect(delegate.toasts.contains('测试提示'), true);
    });

    test('ShareApi 文本分享委派给宿主', () {
      engine.loadAndExecute('share.text("分享文本内容", "主题")');
      expect(delegate.sharedText, '分享文本内容');
    });

    test('ShareApi 文件分享防路径穿越并委派宿主', () async {
      final tempDir = Directory.systemTemp.createTempSync('ptx_share_test_');
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });
      final testFile = File('${tempDir.path}/report.csv')
        ..writeAsStringSync('a,b,c');

      final shareCtx = PluginContext(
        pluginId: 'share_test',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {PluginPermission.storage},
        rootDir: tempDir,
      );
      final shareEngine = LuaEngine(context: shareCtx, delegate: delegate);

      // 1. 越界分享拦截
      expect(
        () => shareEngine.loadAndExecute('share.file("../secret.txt")'),
        throwsException,
      );

      // 2. 正常合法文件分享
      shareEngine.loadAndExecute('''
        share.file("report.csv", "text/csv", "分享报表", function(ok)
          state.set("share_ok", ok)
        end)
      ''');

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(delegate.sharedFilePath, testFile.path);
      expect(delegate.sharedFileMimeType, 'text/csv');
      expect(delegate.sharedFileSubject, '分享报表');
      expect(delegate.getState('share_ok'), true);
    });

    test('SystemApi.openUrl 外部链接跳转委派给宿主', () {
      engine.loadAndExecute('system.openUrl("https://example.com")');
      expect(delegate.openedUrl, 'https://example.com');
    });

    test('MediaApi 未声明 photoLibrary 权限时拒绝 pickImage', () {
      expect(
        () => engine.loadAndExecute('media.pickImage()'),
        throwsException,
      );
    });

    test('MediaApi 声明权限后 pickImage 与 pickFile 正常调用', () async {
      final mediaCtx = PluginContext(
        pluginId: 'media_test',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {PluginPermission.photoLibrary, PluginPermission.storage},
      );
      final mediaEngine = LuaEngine(context: mediaCtx, delegate: delegate);
      delegate.pickedImageResult = 'data/test.jpg';
      delegate.pickedFileResult = 'data/doc.pdf';

      mediaEngine.loadAndExecute('''
        media.pickImage(function(path)
          state.set("image_path", path)
        end)
        media.pickFile(function(path)
          state.set("file_path", path)
        end)
      ''');

      await pumpEventQueue();
      expect(delegate.getState('image_path'), 'data/test.jpg');
      expect(delegate.getState('file_path'), 'data/doc.pdf');
    });

    test('TimerApi setTimeout 与 clear', () async {
      engine.loadAndExecute('''
        timer.setTimeout(10, function()
          state.set("timeout_called", true)
        end)
        local toCancel = timer.setTimeout(500, function()
          state.set("cancelled_called", true)
        end)
        timer.clear(toCancel)
      ''');

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(delegate.getState('timeout_called'), true);
      expect(delegate.getState('cancelled_called'), isNull);
    });

    test('TimerApi clearAll 与 close 自动回收所有定时器', () async {
      engine.loadAndExecute('''
        timer.setTimeout(200, function()
          state.set("never_call", true)
        end)
      ''');
      engine.close();
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(delegate.getState('never_call'), isNull);
    });

    test('FsApi 沙箱文件读写、罗列与路径穿越拦截', () {
      final tempDir = Directory.systemTemp.createTempSync('ptx_fs_test_');
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      final fsCtx = PluginContext(
        pluginId: 'fs_test',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {PluginPermission.storage},
        rootDir: tempDir,
      );
      final fsEngine = LuaEngine(context: fsCtx, delegate: delegate);

      // 1. 路径穿越拦截
      expect(
        () => fsEngine.loadAndExecute('fs.readFile("../../etc/passwd")'),
        throwsException,
      );

      // 2. 正常写入与读取
      fsEngine.loadAndExecute('''
        fs.writeFile("sub/test.txt", "hello sandbox")
        local content = fs.readFile("sub/test.txt")
        state.set("read_content", content)
        state.set("file_exists", fs.exists("sub/test.txt"))
        state.set("not_exists", fs.exists("no_such.txt"))
        
        local stat = fs.stat("sub/test.txt")
        state.set("file_size", stat.size)
        state.set("is_dir", stat.isDirectory)

        local list = fs.listFiles("sub")
        state.set("list_len", #list)
        state.set("list_first", list[1])

        fs.remove("sub/test.txt")
        state.set("after_remove_exists", fs.exists("sub/test.txt"))
      ''');

      expect(delegate.getState('read_content'), 'hello sandbox');
      expect(delegate.getState('file_exists'), true);
      expect(delegate.getState('not_exists'), false);
      expect(delegate.getState('file_size'), 'hello sandbox'.length);
      expect(delegate.getState('is_dir'), false);
      expect(delegate.getState('list_len'), 1);
      expect(delegate.getState('list_first'), 'test.txt');
      expect(delegate.getState('after_remove_exists'), false);
    });

    test('FsApi saveToGallery 与 exportFile 保存与导出', () async {
      final tempDir = Directory.systemTemp.createTempSync('ptx_fs_export_');
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });
      final imgFile = File('${tempDir.path}/pic.png')
        ..writeAsStringSync('fake-png-data');
      final docFile = File('${tempDir.path}/data.csv')
        ..writeAsStringSync('col1,col2');

      final fsCtx = PluginContext(
        pluginId: 'fs_export_test',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {PluginPermission.storage},
        rootDir: tempDir,
      );
      final fsEngine = LuaEngine(context: fsCtx, delegate: delegate);

      // 1. 非图片格式拒绝存入相册
      expect(
        () => fsEngine.loadAndExecute('fs.saveToGallery("data.csv")'),
        throwsException,
      );

      // 2. 正常保存图片到相册
      fsEngine.loadAndExecute('''
        fs.saveToGallery("pic.png", function(ok)
          state.set("gallery_saved", ok)
        end)
      ''');

      // 3. 导出文件到系统
      fsEngine.loadAndExecute('''
        fs.exportFile("data.csv", "my_export.csv", function(ok)
          state.set("exported_ok", ok)
        end)
      ''');

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(delegate.savedGalleryPath, imgFile.path);
      expect(delegate.getState('gallery_saved'), true);
      expect(delegate.exportedFilePath, docFile.path);
      expect(delegate.exportedFileDefaultName, 'my_export.csv');
      expect(delegate.getState('exported_ok'), true);
    });

    test('FsApi 异步非阻塞读写 (readFile, writeFile, readFileAsync, writeFileAsync)', () async {
      final tempDir = Directory.systemTemp.createTempSync('ptx_fs_async_test_');
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      final fsCtx = PluginContext(
        pluginId: 'fs_async_test',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {PluginPermission.storage},
        rootDir: tempDir,
      );
      final fsEngine = LuaEngine(context: fsCtx, delegate: delegate);

      // 1. fs.writeFile 带 callback
      fsEngine.loadAndExecute('''
        fs.writeFile("async_1.txt", "async hello 1", function(ok, err)
          state.set("write_1_ok", ok)
          fs.readFile("async_1.txt", function(content, err)
            state.set("read_1_content", content)
          end)
        end)
      ''');

      // 2. fs.writeFileAsync 与 fs.readFileAsync
      fsEngine.loadAndExecute('''
        fs.writeFileAsync("async_2.txt", "async hello 2", function(ok, err)
          state.set("write_2_ok", ok)
          fs.readFileAsync("async_2.txt", function(content, err)
            state.set("read_2_content", content)
          end)
        end)
      ''');

      // 3. 读取不存在文件的异步错误回调
      fsEngine.loadAndExecute('''
        fs.readFileAsync("not_exist.txt", function(content, err)
          state.set("read_err_content", content == nil)
          state.set("read_err_msg", err)
        end)
      ''');

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(delegate.getState('write_1_ok'), true);
      expect(delegate.getState('read_1_content'), 'async hello 1');
      expect(delegate.getState('write_2_ok'), true);
      expect(delegate.getState('read_2_content'), 'async hello 2');
      expect(delegate.getState('read_err_content'), true);
      expect(delegate.getState('read_err_msg'), contains('文件不存在'));
    });

    test('CryptoApi HMAC 与 SHA512 计算', () {
      engine.loadAndExecute('''
        state.set("h_md5", crypto.hmacMd5("key", "data"))
        state.set("h_sha1", crypto.hmacSha1("key", "data"))
        state.set("h_sha256", crypto.hmacSha256("key", "data"))
        state.set("sha512", crypto.sha512("data"))
      ''');

      expect(delegate.getState('h_md5'), isA<String>());
      expect(delegate.getState('h_sha1'), isA<String>());
      expect(delegate.getState('h_sha256'), isA<String>());
      expect((delegate.getState('sha512') as String).length, 128);
    });

    test('RegexApi 正则匹配、查找与替换', () {
      engine.loadAndExecute('''
        state.set("is_match", regex.test("^\\\\d+\$", "12345"))
        state.set("not_match", regex.test("^\\\\d+\$", "123a"))
        state.set("first", regex.firstMatch("\\\\d+", "abc123def456"))
        
        local all = regex.findAll("\\\\d+", "abc123def456")
        state.set("all_count", #all)
        state.set("all_1", all[1])
        state.set("all_2", all[2])

        state.set("replaced", regex.replace("\\\\d+", "a1b2c", "#"))
        state.set("replaced_all", regex.replaceAll("\\\\d+", "a1b2c", "#"))
      ''');

      expect(delegate.getState('is_match'), true);
      expect(delegate.getState('not_match'), false);
      expect(delegate.getState('first'), '123');
      expect(delegate.getState('all_count'), 2);
      expect(delegate.getState('all_1'), '123');
      expect(delegate.getState('all_2'), '456');
      expect(delegate.getState('replaced'), 'a#b2c');
      expect(delegate.getState('replaced_all'), 'a#b#c');
    });

    test('ColorApi Hex, RGB 与 HSL 颜色空间互相转换', () {
      engine.loadAndExecute('''
        local rgb = color.hexToRgb("#FF8000")
        state.set("rgb_r", rgb.r)
        state.set("rgb_g", rgb.g)
        state.set("rgb_b", rgb.b)

        state.set("hex_str", color.rgbToHex(255, 128, 0))

        local hsl = color.rgbToHsl(255, 0, 0)
        state.set("hsl_h", hsl.h)
        state.set("hsl_s", hsl.s)
        state.set("hsl_l", hsl.l)

        local fromHsl = color.hslToRgb(0, 1.0, 0.5)
        state.set("from_h_r", fromHsl.r)
        state.set("from_h_g", fromHsl.g)
        state.set("from_h_b", fromHsl.b)
      ''');

      expect(delegate.getState('rgb_r'), 255);
      expect(delegate.getState('rgb_g'), 128);
      expect(delegate.getState('rgb_b'), 0);
      expect(delegate.getState('hex_str'), '#FF8000');
      expect(delegate.getState('hsl_h'), 0.0);
      expect(delegate.getState('hsl_s'), 1.0);
      expect(delegate.getState('hsl_l'), 0.5);
      expect(delegate.getState('from_h_r'), 255);
      expect(delegate.getState('from_h_g'), 0);
      expect(delegate.getState('from_h_b'), 0);
    });

    test('UtilApi formatTime 与 parseTime', () {
      engine.loadAndExecute('''
        local ms = 1700000000000
        local formatted = util.formatTime(ms, "yyyy-MM-dd HH:mm:ss")
        state.set("formatted", formatted)
        local parsed = util.parseTime(formatted, "yyyy-MM-dd HH:mm:ss")
        state.set("parsed_ms", parsed)
      ''');

      expect(delegate.getState('formatted'), isA<String>());
      expect(delegate.getState('parsed_ms'), 1700000000000);
    });

    test('NetworkApi 支持 put, delete 与 request 方法绑定', () {
      engine.loadAndExecute('''
        state.set("has_put", type(network.put))
        state.set("has_delete", type(network.delete))
        state.set("has_request", type(network.request))
      ''');

      expect(delegate.getState('has_put'), 'function');
      expect(delegate.getState('has_delete'), 'function');
      expect(delegate.getState('has_request'), 'function');
    });

    test('FsApi 扩展: readHex, writeHex, copy, move 与 fileSize', () {
      final tempDir = Directory.systemTemp.createTempSync('ptx_fs_ext_');
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      final fsCtx = PluginContext(
        pluginId: 'fs_ext_test',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {PluginPermission.storage},
        rootDir: tempDir,
      );
      final fsEngine = LuaEngine(context: fsCtx, delegate: delegate);

      fsEngine.loadAndExecute('''
        -- 写入十六进制数据 (对应 ASCII: "Antigravity")
        -- "416e746967726176697479"
        local ok = fs.writeHex("test_bin.dat", "416e746967726176697479")
        state.set("write_ok", ok)
        state.set("bin_size", fs.fileSize("test_bin.dat"))
        state.set("read_hex", fs.readHex("test_bin.dat"))
        state.set("read_hex_sub", fs.readHex("test_bin.dat", 0, 4))

        -- 测试沙箱内复制与移动
        fs.copy("test_bin.dat", "copy_bin.dat")
        state.set("copy_exists", fs.exists("copy_bin.dat"))

        fs.move("copy_bin.dat", "moved_bin.dat")
        state.set("moved_exists", fs.exists("moved_bin.dat"))
        state.set("old_exists", fs.exists("copy_bin.dat"))
      ''');

      expect(delegate.getState('write_ok'), isTrue);
      expect(delegate.getState('bin_size'), 11);
      expect(delegate.getState('read_hex'), '416e746967726176697479');
      expect(delegate.getState('read_hex_sub'), '416e7469');
      expect(delegate.getState('copy_exists'), isTrue);
      expect(delegate.getState('moved_exists'), isTrue);
      expect(delegate.getState('old_exists'), isFalse);
    });

    test('FsApi 扩展: pickFile, writeBase64, readBase64 与 hash', () async {
      final tempDir = Directory.systemTemp.createTempSync('ptx_fs_hash_');
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      final fsCtx = PluginContext(
        pluginId: 'fs_hash_test',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {PluginPermission.storage},
        rootDir: tempDir,
      );
      delegate.pickedFileResult = 'data/mock_file.txt';
      final fsEngine = LuaEngine(context: fsCtx, delegate: delegate);

      fsEngine.loadAndExecute('''
        -- 写入 Base64 (对应 ASCII: "Hello PluginToolbox")
        -- SGVsbG8gUGx1Z2luVG9vbGJveA==
        local ok = fs.writeBase64("hello.txt", "SGVsbG8gUGx1Z2luVG9vbGJveA==")
        state.set("b64_write_ok", ok)
        state.set("b64_read", fs.readBase64("hello.txt"))

        -- 计算各种哈希
        local md5_val = fs.hash("hello.txt", "md5")
        local sha1_val = fs.hash("hello.txt", "sha1")
        local sha256_val = fs.hash("hello.txt", "sha256")
        local crc_val = fs.hash("hello.txt", "crc32")
        state.set("file_md5", md5_val)
        state.set("file_sha1", sha1_val)
        state.set("file_sha256", sha256_val)
        state.set("file_crc32", crc_val)

        -- 全量信息表
        local meta = fs.hash("hello.txt")
        state.set("meta_name", meta.name)
        state.set("meta_size", meta.size)
        state.set("meta_ext", meta.extension)
        state.set("meta_md5", meta.md5)

        -- pickFile 回调
        fs.pickFile(function(path)
          state.set("picked_path", path)
        end)
      ''');

      await Future.delayed(const Duration(milliseconds: 50));

      expect(delegate.getState('b64_write_ok'), isTrue);
      expect(delegate.getState('b64_read'), 'SGVsbG8gUGx1Z2luVG9vbGJveA==');
      expect(delegate.getState('file_md5'), isNotEmpty);
      expect(delegate.getState('file_sha1'), isNotEmpty);
      expect(delegate.getState('file_sha256'), isNotEmpty);
      expect(delegate.getState('file_crc32'), isNotEmpty);
      expect(delegate.getState('meta_name'), 'hello.txt');
      expect(delegate.getState('meta_size'), 19);
      expect(delegate.getState('meta_ext'), 'txt');
      expect(delegate.getState('meta_md5'), delegate.getState('file_md5'));
      expect(delegate.getState('picked_path'), 'data/mock_file.txt');
    });

    test('ArchiveApi: zip, list 与 unzip', () {
      final tempDir = Directory.systemTemp.createTempSync('ptx_archive_');
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      final arcCtx = PluginContext(
        pluginId: 'archive_test',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {PluginPermission.storage},
        rootDir: tempDir,
      );
      final arcEngine = LuaEngine(context: arcCtx, delegate: delegate);

      arcEngine.loadAndExecute('''
        -- 准备测试文件
        fs.writeFile("sub/f1.txt", "hello")
        fs.writeFile("sub/f2.txt", "world")

        -- 压缩目录
        local zipOk = archive.zip("sub", "bundle.zip")
        state.set("zip_ok", zipOk)

        -- 读取条目列表
        local list = archive.list("bundle.zip")
        state.set("list_len", #list)

        -- 解压到新目录
        local unzipOk = archive.unzip("bundle.zip", "unpacked")
        state.set("unzip_ok", unzipOk)
        state.set("f1_content", fs.readFile("unpacked/f1.txt"))
        state.set("f2_content", fs.readFile("unpacked/f2.txt"))
      ''');

      expect(delegate.getState('zip_ok'), isTrue);
      expect(delegate.getState('list_len'), 2);
      expect(delegate.getState('unzip_ok'), isTrue);
      expect(delegate.getState('f1_content'), 'hello');
      expect(delegate.getState('f2_content'), 'world');
    });

    test('DocumentApi: csvParse 与 csvStringify 往返转换', () {
      engine.loadAndExecute('''
        local csv = 'name,score,desc\\nAlice,100,"good, job"\\nBob,90,"said ""hi"""'
        local rows = document.csvParse(csv)
        state.set("row_count", #rows)
        state.set("r1_c1", rows[1][1])
        state.set("r2_c3", rows[2][3])
        state.set("r3_c3", rows[3][3])

        local stringified = document.csvStringify(rows)
        state.set("stringified", stringified)
        local re_rows = document.csvParse(stringified)
        state.set("re_row_count", #re_rows)
        state.set("re_r2_c3", re_rows[2][3])
      ''');

      expect(delegate.getState('row_count'), 3);
      expect(delegate.getState('r1_c1'), 'name');
      expect(delegate.getState('r2_c3'), 'good, job');
      expect(delegate.getState('r3_c3'), 'said "hi"');
      expect(delegate.getState('re_row_count'), 3);
      expect(delegate.getState('re_r2_c3'), 'good, job');
    });

    test('DocumentApi: markdownToHtml 标题、强调与代码块', () {
      engine.loadAndExecute('''
        local md = "# Hello\\n**Bold text** and `inline code`\\n- Item 1\\n- Item 2"
        local html = document.markdownToHtml(md)
        state.set("html", html)
      ''');

      final html = delegate.getState('html') as String;
      expect(html, contains('<h1>Hello</h1>'));
      expect(html, contains('<strong>Bold text</strong>'));
      expect(html, contains('<code>inline code</code>'));
      expect(html, contains('<li>Item 1</li>'));
      expect(html, contains('<li>Item 2</li>'));
    });

    test('TorchApi: 权限控制与开关状态', () {
      // 未声明权限报错
      expect(
        () => engine.loadAndExecute('torch.on()'),
        throwsA(isA<Exception>()),
      );

      // 声明权限后测试
      final torchCtx = PluginContext(
        pluginId: 'torch_test',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {PluginPermission.torch},
      );
      final torchEngine = LuaEngine(context: torchCtx, delegate: delegate);

      torchEngine.loadAndExecute('''
        state.set("init_torch", torch.isOn())
        torch.on()
      ''');
      expect(delegate.getState('init_torch'), isFalse);
      expect(delegate.torchState, isTrue);

      torchEngine.loadAndExecute('''
        torch.off()
      ''');
      expect(delegate.torchState, isFalse);
    });

    test('QrcodeApi: 生成二维码矩阵与尺寸', () {
      engine.loadAndExecute('''
        local res = qrcode.matrix("https://github.com")
        state.set("qr_cols", res.cols)
        state.set("qr_rows", res.rows)
        state.set("qr_len", string.len(res.data))
      ''');

      final cols = delegate.getState('qr_cols') as int;
      final rows = delegate.getState('qr_rows') as int;
      final len = delegate.getState('qr_len') as int;

      expect(cols, greaterThan(0));
      expect(rows, cols);
      expect(len, cols * rows);
    });

    test('CameraApi: 权限控制与扫码识别', () async {
      // 1. 未声明 camera 权限时拦截
      expect(
        () => engine.loadAndExecute('camera.scan()'),
        throwsA(isA<Exception>()),
      );

      // 2. 声明 camera 权限
      final camCtx = PluginContext(
        pluginId: 'camera_test',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {PluginPermission.camera, PluginPermission.storage},
      );
      final camEngine = LuaEngine(context: camCtx, delegate: delegate);

      // 回调方式
      camEngine.loadAndExecute('''
        camera.scan("请对准二维码", function(code)
          state.set("scanned_via_cb", code)
        end)
      ''');

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(delegate.getState('scanned_via_cb'), 'https://example.com/mock-qr');

      // 默认状态写入方式
      camEngine.loadAndExecute('camera.scan()');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(delegate.getState('__scanned_code'), 'https://example.com/mock-qr');
    });

    test('CameraApi & VisionApi: 离线图片条码解码与沙箱防护', () async {
      final tempDir = Directory.systemTemp.createTempSync('ptx_vision_test_');
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });
      File('${tempDir.path}/qr.png').writeAsStringSync('fake-qr');

      final visionCtx = PluginContext(
        pluginId: 'vision_test',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {PluginPermission.storage, PluginPermission.camera},
        rootDir: tempDir,
      );
      final visionEngine = LuaEngine(context: visionCtx, delegate: delegate);

      // 1. 路径穿越拦截
      expect(
        () => visionEngine.loadAndExecute('vision.decodeBarcode("../../secret.png")'),
        throwsException,
      );
      expect(
        () => visionEngine.loadAndExecute('camera.decodeImage("../../secret.png")'),
        throwsException,
      );

      // 2. 合法沙箱图片解码 (vision.decodeBarcode)
      visionEngine.loadAndExecute('''
        vision.decodeBarcode("qr.png", function(res)
          state.set("vision_decoded", res)
        end)
      ''');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(delegate.getState('vision_decoded'), 'mock-decoded-barcode-123');

      // 3. camera.decodeImage 无回调写入 __decoded_code
      visionEngine.loadAndExecute('camera.decodeImage("qr.png")');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(delegate.getState('__decoded_code'), 'mock-decoded-barcode-123');
    });

    test('SensorApi: 权限控制、可用性查询与传感器数据周期流转', () async {
      // 1. 未声明 sensor 权限时报错
      expect(
        () => engine.loadAndExecute('sensor.isAvailable("accelerometer")'),
        throwsA(isA<Exception>()),
      );

      // 2. 声明 sensor 权限
      final sensorCtx = PluginContext(
        pluginId: 'sensor_test',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {PluginPermission.sensor},
      );
      final sensorEngine = LuaEngine(context: sensorCtx, delegate: delegate);

      // 3. 可用性判断
      sensorEngine.loadAndExecute('''
        state.set("has_acc", sensor.isAvailable("accelerometer"))
        state.set("has_gyro", sensor.isAvailable("gyroscope"))
        state.set("has_comp", sensor.isAvailable("compass"))
        state.set("has_mag", sensor.isAvailable("magnetometer"))
        state.set("has_foo", sensor.isAvailable("unknown_sensor"))
      ''');
      expect(delegate.getState('has_acc'), isTrue);
      expect(delegate.getState('has_gyro'), isTrue);
      expect(delegate.getState('has_comp'), isTrue);
      expect(delegate.getState('has_mag'), isTrue);
      expect(delegate.getState('has_foo'), isFalse);

      // 4. 启动监听并接收周期回调与状态自动写入
      sensorEngine.loadAndExecute('''
        sensor.start("accelerometer", function(data)
          state.set("acc_x", data.x)
          state.set("acc_y", data.y)
          state.set("acc_z", data.z)
        end)
      ''');

      // 等待 150ms 触发至少一次周期轮询
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(delegate.startedSensors.contains('accelerometer'), isTrue);
      expect(delegate.getState('acc_x'), 1.0);
      expect(delegate.getState('acc_y'), 2.0);
      expect(delegate.getState('acc_z'), 9.8);
      expect(delegate.getState('__sensor_accelerometer'), isNotNull);

      // 5. 即时读取最新缓存值
      sensorEngine.loadAndExecute('''
        local cur = sensor.get("accelerometer")
        state.set("cache_x", cur.x)
        local curAcc = sensor.getAccelerometer()
        state.set("acc_func_y", curAcc.y)
      ''');
      expect(delegate.getState('cache_x'), 1.0);
      expect(delegate.getState('acc_func_y'), 2.0);

      // 6. 停止监听单个传感器
      sensorEngine.loadAndExecute('sensor.stop("accelerometer")');
      expect(delegate.stoppedSensors.contains('accelerometer'), isTrue);

      // 7. 关闭引擎自动释放全部传感器监听
      sensorEngine.close();
      expect(delegate.stoppedSensors.contains('all'), isTrue);
    });

    test('ImageApi: 权限控制、沙箱防护与图像处理能力', () async {
      // 1. 未声明 storage 权限时拦截
      final noStorageCtx = PluginContext(
        pluginId: 'img_no_perm',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {},
      );
      final noStorageEngine =
          LuaEngine(context: noStorageCtx, delegate: delegate);
      expect(
        () => noStorageEngine.loadAndExecute('image.info("pic.jpg")'),
        throwsA(isA<Exception>()),
      );

      // 2. 声明 storage 权限
      final tempDir = Directory.systemTemp.createTempSync('ptx_image_test_');
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });
      File('${tempDir.path}/pic.jpg').writeAsStringSync('fake-jpeg');

      final imgCtx = PluginContext(
        pluginId: 'img_test',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {PluginPermission.storage},
        rootDir: tempDir,
      );
      final imgEngine = LuaEngine(context: imgCtx, delegate: delegate);

      // 3. 越界沙箱路径拦截
      expect(
        () => imgEngine.loadAndExecute('image.compress("../../evil.jpg", 50)'),
        throwsException,
      );

      // 4. image.info 读取信息
      imgEngine.loadAndExecute('''
        image.info("pic.jpg", function(info)
          state.set("info_w", info.width)
          state.set("info_h", info.height)
          state.set("info_fmt", info.format)
        end)
      ''');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(delegate.getState('info_w'), 800);
      expect(delegate.getState('info_h'), 600);
      expect(delegate.getState('info_fmt'), 'image/jpeg');

      // 5. image.compress
      imgEngine.loadAndExecute('''
        image.compress("pic.jpg", 70, function(target)
          state.set("comp_dest", target)
        end)
      ''');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(delegate.compressedQuality, 70);
      expect(delegate.getState('comp_dest'), contains('compressed.jpg'));

      // 6. image.crop
      imgEngine.loadAndExecute('''
        image.crop("pic.jpg", 10, 20, 100, 150, function(target)
          state.set("crop_dest", target)
        end)
      ''');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(delegate.getState('crop_dest'), contains('cropped.png'));

      // 7. image.convert
      imgEngine.loadAndExecute('''
        image.convert("pic.jpg", "webp", function(target)
          state.set("conv_dest", target)
        end)
      ''');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(delegate.convertedFormat, 'webp');
      expect(delegate.getState('conv_dest'), contains('.webp'));

      // 8. image.stripExif
      imgEngine.loadAndExecute('''
        image.stripExif("pic.jpg", function(target)
          state.set("exif_dest", target)
        end)
      ''');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(delegate.getState('exif_dest'), contains('clean.jpg'));
    });

    test('NotificationApi: 权限控制与通知调度流转', () async {
      // 1. 未声明 notification 权限时报错
      expect(
        () => engine.loadAndExecute('notification.show("测试", "内容")'),
        throwsA(isA<Exception>()),
      );

      // 2. 声明 notification 权限
      final notifCtx = PluginContext(
        pluginId: 'notif_test',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {PluginPermission.notification},
      );
      final notifEngine = LuaEngine(context: notifCtx, delegate: delegate);

      // 3. 即时通知
      notifEngine.loadAndExecute('''
        notification.show("即时提醒", "喝水时间到了", function(id)
          state.set("shown_id", id)
        end)
      ''');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(delegate.sentNotifications.length, 1);
      expect(delegate.sentNotifications.first['title'], '即时提醒');
      expect(delegate.getState('shown_id'), isNotNull);

      // 4. 定时调度通知
      notifEngine.loadAndExecute('''
        notification.schedule("番茄钟", "专注结束", 1500, function(id)
          state.set("sched_id", id)
        end)
      ''');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(delegate.sentNotifications.length, 2);
      expect(delegate.sentNotifications.last['delaySeconds'], 1500);

      // 5. 取消指定通知与全部取消
      notifEngine.loadAndExecute('''
        notification.cancel(101)
        notification.cancelAll()
      ''');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(delegate.cancelledNotificationIds.contains(101), isTrue);
      expect(delegate.cancelledAllNotifs, isTrue);
    });

    test('AudioApi: 音频播放、停止与频率合成器', () async {
      final tempDir = Directory.systemTemp.createTempSync('ptx_audio_test_');
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });
      File('${tempDir.path}/bell.mp3').writeAsStringSync('fake-audio');

      final audioCtx = PluginContext(
        pluginId: 'audio_test',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {PluginPermission.storage},
        rootDir: tempDir,
      );
      final audioEngine = LuaEngine(context: audioCtx, delegate: delegate);

      // 1. 越界播放拦截
      expect(
        () => audioEngine.loadAndExecute('audio.play("../escape.mp3")'),
        throwsException,
      );

      // 2. 正常播放与停止
      audioEngine.loadAndExecute('''
        audio.play("bell.mp3", function(ok)
          state.set("audio_ok", ok)
        end)
        audio.stop()
      ''');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(delegate.playedAudioPath, contains('bell.mp3'));
      expect(delegate.getState('audio_ok'), isTrue);
      expect(delegate.audioStopped, isTrue);

      // 3. playTone 正弦波合成音
      audioEngine.loadAndExecute('''
        audio.playTone(440, 300, function(ok)
          state.set("tone_ok", ok)
        end)
      ''');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(delegate.playedToneFreq, 440.0);
      expect(delegate.playedToneDuration, 300);
      expect(delegate.getState('tone_ok'), isTrue);

      // 4. close 释放
      delegate.audioStopped = false;
      audioEngine.close();
      expect(delegate.audioStopped, isTrue);
    });

    test('DialogApi: prompt 与 pickItem 高级弹窗交互', () async {
      engine.loadAndExecute('''
        dialog.prompt("输入密码", "请输入8位字符", function(text)
          state.set("pwd_input", text)
        end)

        dialog.pickItem("选择进制", {"二进制", "八进制", "十六进制"}, 1, function(item, idx)
          state.set("picked_item", item)
          state.set("picked_idx", idx)
        end)

        dialog.bottomSheet("快捷菜单", {"选项A", "选项B"}, function(item, idx)
          state.set("sheet_item", item)
          state.set("sheet_idx", idx)
        end)
      ''');

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(delegate.getState('pwd_input'), 'user-inputted-text');
      expect(delegate.getState('picked_item'), 'Option 2');
      expect(delegate.getState('picked_idx'), 2);
      expect(delegate.getState('sheet_item'), 'Item 1');
      expect(delegate.getState('sheet_idx'), 1);
    });

    test('SystemApi: 电池电量与网络感知', () async {
      // 1. 同步读取
      engine.loadAndExecute('''
        state.set("batt_sync", system.batteryLevel())
        state.set("charge_sync", system.isCharging())
        state.set("net_sync", system.networkType())
      ''');
      expect(delegate.getState('batt_sync'), 85);
      expect(delegate.getState('charge_sync'), isTrue);
      expect(delegate.getState('net_sync'), 'wifi');

      // 2. 异步回调读取
      engine.loadAndExecute('''
        system.batteryLevel(function(lvl)
          state.set("batt_async", lvl)
        end)
        system.isCharging(function(chg)
          state.set("charge_async", chg)
        end)
        system.networkType(function(net)
          state.set("net_async", net)
        end)
      ''');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(delegate.getState('batt_async'), 85);
      expect(delegate.getState('charge_async'), isTrue);
      expect(delegate.getState('net_async'), 'wifi');
    });

    test('SocketApi: 权限控制与 TCP/UDP 套接字接口', () async {
      // 1. 无 network 权限时被拒绝
      final noNetCtx = PluginContext(
        pluginId: 'no_net',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {},
      );
      final noNetEngine = LuaEngine(context: noNetCtx, delegate: delegate);
      expect(
        () => noNetEngine.loadAndExecute('socket.tcpConnect("127.0.0.1", 8080, {})'),
        throwsException,
      );
      expect(
        () => noNetEngine.loadAndExecute('socket.udpBind(8080, {})'),
        throwsException,
      );

      // 2. 有 network 权限时正常调用
      final netCtx = PluginContext(
        pluginId: 'net_test',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {PluginPermission.network},
      );
      final netEngine = LuaEngine(context: netCtx, delegate: delegate);

      netEngine.loadAndExecute('''
        local id = socket.tcpConnect("127.0.0.1", 9999, {
          onConnect = function(sId) state.set("tcp_conn", sId) end,
          onError = function(sId, err) state.set("tcp_err", err) end,
        })
        state.set("tcp_id", id)

        local okSend = socket.tcpSend(id, "ping")
        state.set("tcp_send_ok", okSend)

        local okClose = socket.tcpClose(id)
        state.set("tcp_close_ok", okClose)

        local udpId = socket.udpBind(0, {
          onData = function(uId, data, addr, port) state.set("udp_data", data) end,
        })
        state.set("udp_id", udpId)
        local okUdpSend = socket.udpSend(udpId, "127.0.0.1", 9999, "hello")
        state.set("udp_send_ok", okUdpSend)
        local okUdpClose = socket.udpClose(udpId)
        state.set("udp_close_ok", okUdpClose)
      ''');

      expect(delegate.getState('tcp_id'), startsWith('tcp_'));
      expect(delegate.getState('udp_id'), startsWith('udp_'));
      expect(delegate.getState('tcp_close_ok'), isTrue);
      expect(delegate.getState('udp_close_ok'), isTrue);

      netEngine.close();
    });

    test('WebSocketApi: 权限控制与接口绑定', () async {
      // 1. 无 network 权限拒绝
      final noNetCtx = PluginContext(
        pluginId: 'no_net',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {},
      );
      final noNetEngine = LuaEngine(context: noNetCtx, delegate: delegate);
      expect(
        () => noNetEngine.loadAndExecute('websocket.connect("ws://127.0.0.1:8080", {})'),
        throwsException,
      );

      // 2. 有 network 权限
      final netCtx = PluginContext(
        pluginId: 'net_test',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {PluginPermission.network},
      );
      final netEngine = LuaEngine(context: netCtx, delegate: delegate);

      netEngine.loadAndExecute('''
        local wsId = websocket.connect("ws://127.0.0.1:9999", {
          onOpen = function(id) state.set("ws_open", id) end,
          onError = function(id, err) state.set("ws_err", err) end,
        })
        state.set("ws_id", wsId)
        local sent = websocket.send(wsId, "test")
        state.set("ws_sent", sent)
        local closed = websocket.close(wsId)
        state.set("ws_closed", closed)
      ''');

      expect(delegate.getState('ws_id'), startsWith('ws_'));
      expect(delegate.getState('ws_sent'), isFalse); // 未连上未入表
      expect(delegate.getState('ws_closed'), isTrue);

      netEngine.close();
    });

    test('NetworkApi: resolveDns, ping 与 scanPort 诊断绑定', () async {
      final netCtx = PluginContext(
        pluginId: 'net_test',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {PluginPermission.network},
      );
      final netEngine = LuaEngine(context: netCtx, delegate: delegate);

      netEngine.loadAndExecute('''
        network.resolveDns("127.0.0.1", function(res)
          state.set("dns_ok", res.ok)
          state.set("dns_ips", res.addresses[1])
        end)

        network.ping("127.0.0.1", { port = 80, timeoutMs = 100 }, function(res)
          state.set("ping_done", true)
          state.set("ping_host", res.host)
        end)

        network.scanPort("127.0.0.1", 65534, 100, function(res)
          state.set("scan_done", true)
          state.set("scan_open", res.open)
        end)
      ''');

      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(delegate.getState('dns_ok'), isTrue);
      expect(delegate.getState('dns_ips'), '127.0.0.1');
      expect(delegate.getState('ping_done'), isTrue);
      expect(delegate.getState('ping_host'), '127.0.0.1');
      expect(delegate.getState('scan_done'), isTrue);
      expect(delegate.getState('scan_open'), isFalse);

      netEngine.close();
    });

    test('BiometricsApi: 权限拦截与生物识别核验绑定', () async {
      // 1. 无权限时报错
      final noPermEngine = LuaEngine(context: context, delegate: delegate);
      expect(
        () => noPermEngine.loadAndExecute('biometrics.isAvailable()'),
        throwsException,
      );
      noPermEngine.close();

      // 2. 有权限时调用
      final bioCtx = PluginContext(
        pluginId: 'bio_test',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {PluginPermission.biometrics},
      );
      final bioEngine = LuaEngine(context: bioCtx, delegate: delegate);

      bioEngine.loadAndExecute('''
        biometrics.isAvailable(function(avail)
          state.set("bio_avail", avail)
        end)
        biometrics.authenticate("请验证指纹", function(res)
          state.set("bio_success", res.success)
        end)
      ''');

      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(delegate.getState('bio_avail'), isTrue);
      expect(delegate.getState('bio_success'), isTrue);

      bioEngine.close();
    });

    test('AudioApi: 录音与分贝感知 (权限校验、防路径穿越与回调)', () async {
      // 1. 无权限时报错
      final noPermEngine = LuaEngine(context: context, delegate: delegate);
      expect(
        () => noPermEngine.loadAndExecute('audio.startRecord("data/test.m4a")'),
        throwsException,
      );
      expect(
        () => noPermEngine.loadAndExecute('audio.getDecibel()'),
        throwsException,
      );
      noPermEngine.close();

      // 2. 有权限但路径逃逸沙箱
      final tempDir = await Directory.systemTemp.createTemp('ptx_audio_test');
      final audioCtx = PluginContext(
        pluginId: 'audio_test',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        rootDir: tempDir,
        grantedPermissions: {
          PluginPermission.microphone,
          PluginPermission.storage,
        },
      );
      final audioEngine = LuaEngine(context: audioCtx, delegate: delegate);

      expect(
        () => audioEngine.loadAndExecute('audio.startRecord("../escape.m4a")'),
        throwsException,
      );

      // 3. 正常录音流程与分贝检测
      audioEngine.loadAndExecute('''
        audio.startRecord("data/rec.m4a", function(ok)
          state.set("rec_started", ok)
        end)
        audio.getDecibel(function(db)
          state.set("rec_db", db)
        end)
        audio.stopRecord(function(info)
          state.set("rec_stopped", true)
          state.set("rec_path", info.path)
        end)
      ''');

      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(delegate.getState('rec_started'), isTrue);
      expect(delegate.getState('rec_db'), 65.5);
      expect(delegate.getState('rec_stopped'), isTrue);
      expect(delegate.getState('rec_path'), contains('rec.m4a'));

      audioEngine.close();
      await tempDir.delete(recursive: true);
    });

    test('SystemApi: speak 与 stopSpeak 语音合成调用', () async {
      engine.loadAndExecute('''
        system.speak("Hello Toolbox", { language = "zh-CN", pitch = 1.2, rate = 0.9 }, function(ok)
          state.set("speak_ok", ok)
        end)
        system.stopSpeak(function(ok)
          state.set("stop_speak_ok", ok)
        end)
      ''');

      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(delegate.getState('speak_ok'), isTrue);
      expect(delegate.spokenText, 'Hello Toolbox');
      expect(delegate.spokenLanguage, 'zh-CN');
      expect(delegate.spokenPitch, 1.2);
      expect(delegate.spokenRate, 0.9);
      expect(delegate.getState('stop_speak_ok'), isTrue);
      expect(delegate.speechStopped, isTrue);
    });

    test('TaskApi: task.run 后台 Worker 并发计算与回调通知', () async {
      engine.loadAndExecute('''
        -- 1. 携带 main(args) 函数的 Worker 计算
        task.run([[
          function main(args)
            return args.a + args.b
          end
        ]], { a = 12, b = 30 }, function(res)
          state.set("task_sum_ok", res.ok)
          state.set("task_sum_val", res.result)
        end)

        -- 2. 直接 return 表达式的轻量 Worker 计算
        task.run("return string.upper('hello worker')", function(res)
          state.set("task_upper_ok", res.ok)
          state.set("task_upper_val", res.result)
        end)

        -- 3. 语法错误时返回 ok=false 并捕获错误原因
        task.run("syntax error !!!", function(res)
          state.set("task_err_ok", res.ok)
          state.set("task_err_has_msg", res.error ~= nil)
        end)
      ''');

      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(delegate.getState('task_sum_ok'), isTrue);
      expect(delegate.getState('task_sum_val'), 42);
      expect(delegate.getState('task_upper_ok'), isTrue);
      expect(delegate.getState('task_upper_val'), 'HELLO WORKER');
      expect(delegate.getState('task_err_ok'), isFalse);
      expect(delegate.getState('task_err_has_msg'), isTrue);
    });

    test('TaskApi: task.parallel 并发执行多任务聚合', () async {
      engine.loadAndExecute('''
        local tasks = {
          { script = "return 10 * 2" },
          { script = "function main(x) return x .. ' world' end", args = "hello" },
          { script = "return hash.md5('toolbox')" }
        }

        task.parallel(tasks, function(res)
          state.set("parallel_ok", res.ok)
          state.set("parallel_res1", res.results[1].result)
          state.set("parallel_res2", res.results[2].result)
          state.set("parallel_res3", res.results[3].result)
        end)
      ''');

      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(delegate.getState('parallel_ok'), isTrue);
      expect(delegate.getState('parallel_res1'), 20);
      expect(delegate.getState('parallel_res2'), 'hello world');
      expect(delegate.getState('parallel_res3'), isNotEmpty);
    });

    test('FsApi: 沙箱存储配额检测超限拒绝写入', () async {
      final tempDir = await Directory.systemTemp.createTemp('ptx_lua_quota_test');
      // 配额设为 0MB，任何写入均被拒绝
      final quotaCtx = PluginContext(
        pluginId: 'quota_fs_test',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        rootDir: tempDir,
        storageQuotaMb: 0,
        grantedPermissions: {PluginPermission.storage},
      );
      final quotaEngine = LuaEngine(context: quotaCtx, delegate: delegate);

      expect(
        () => quotaEngine.loadAndExecute('fs.writeFile("test.txt", "hello")'),
        throwsException,
      );

      quotaEngine.close();
      await tempDir.delete(recursive: true);
    });

    test('ScreenApi: 权限控制、常亮与亮度设置及资源还原', () async {
      // 1. 无权限拦截
      expect(
        () => engine.loadAndExecute('screen.setKeepScreenOn(true)'),
        throwsException,
      );

      // 2. 有权限执行
      final screenCtx = PluginContext(
        pluginId: 'screen_test',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {PluginPermission.screen},
      );
      final screenEngine = LuaEngine(context: screenCtx, delegate: delegate);

      screenEngine.loadAndExecute('''
        screen.setKeepScreenOn(true, function(ok)
          state.set("screen_on_ok", ok)
        end)
        screen.setBrightness(0.75, function(ok)
          state.set("brightness_set_ok", ok)
        end)
      ''');

      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(delegate.keepScreenOn, isTrue);
      expect(delegate.screenBrightness, 0.75);
      expect(delegate.getState('screen_on_ok'), isTrue);
      expect(delegate.getState('brightness_set_ok'), isTrue);

      // close 还原状态
      screenEngine.close();
      expect(delegate.keepScreenOn, isFalse);
      expect(delegate.brightnessReset, isTrue);
    });

    test('LocationApi: 权限控制与定位数据获取', () async {
      // 1. 无权限拦截
      expect(
        () => engine.loadAndExecute('location.getCurrentPosition(function() end)'),
        throwsException,
      );

      // 2. 有权限获取
      final locCtx = PluginContext(
        pluginId: 'loc_test',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {PluginPermission.location},
      );
      final locEngine = LuaEngine(context: locCtx, delegate: delegate);

      locEngine.loadAndExecute('''
        location.isAvailable(function(avail)
          state.set("loc_avail", avail)
        end)
        location.getCurrentPosition(function(res)
          state.set("loc_ok", res.ok)
          state.set("loc_lat", res.latitude)
          state.set("loc_lng", res.longitude)
        end)
        location.getAltitude(function(alt)
          state.set("loc_alt", alt)
        end)
      ''');

      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(delegate.getState('loc_avail'), isTrue);
      expect(delegate.getState('loc_ok'), isTrue);
      expect(delegate.getState('loc_lat'), 31.2304);
      expect(delegate.getState('loc_lng'), 121.4737);
      expect(delegate.getState('loc_alt'), 15.5);
    });

    test('NfcApi: 权限控制与 NDEF 标签读写', () async {
      // 1. 无权限拦截
      expect(
        () => engine.loadAndExecute('nfc.readNdef(function() end)'),
        throwsException,
      );

      // 2. 有权限读写
      final nfcCtx = PluginContext(
        pluginId: 'nfc_test',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {PluginPermission.nfc},
      );
      final nfcEngine = LuaEngine(context: nfcCtx, delegate: delegate);

      nfcEngine.loadAndExecute('''
        nfc.isAvailable(function(avail)
          state.set("nfc_avail", avail)
        end)
        nfc.readNdef(function(res)
          state.set("nfc_read_ok", res.ok)
          state.set("nfc_read_payload", res.records[1].payload)
        end)
        nfc.writeNdef({ { type = "text", payload = "New NFC Tag" } }, function(res)
          state.set("nfc_write_ok", res.ok)
        end)
      ''');

      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(delegate.getState('nfc_avail'), isTrue);
      expect(delegate.getState('nfc_read_ok'), isTrue);
      expect(delegate.getState('nfc_read_payload'), 'Hello NFC');
      expect(delegate.getState('nfc_write_ok'), isTrue);
      expect(delegate.writtenNdefRecords.first['payload'], 'New NFC Tag');
    });

    test('BluetoothApi: 权限控制、扫描、连接与特征值读写', () async {
      // 1. 无权限拦截
      expect(
        () => engine.loadAndExecute('bluetooth.startScan(function() end)'),
        throwsException,
      );

      // 2. 有权限扫描与操作
      final bleCtx = PluginContext(
        pluginId: 'ble_test',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {PluginPermission.bluetooth},
      );
      final bleEngine = LuaEngine(context: bleCtx, delegate: delegate);

      bleEngine.loadAndExecute('''
        bluetooth.startScan(function(res)
          state.set("ble_scan_dev", res.device.name)
        end)
        bluetooth.connect("AA:BB:CC", function(res)
          state.set("ble_conn_ok", res.ok)
        end)
        bluetooth.read("AA:BB:CC", "180D", "2A37", function(res)
          state.set("ble_read_val", res.value)
        end)
        bluetooth.write("AA:BB:CC", "180D", "2A37", "FFEE", function(res)
          state.set("ble_write_ok", res.ok)
        end)
      ''');

      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(delegate.getState('ble_scan_dev'), 'Test Beacon');
      expect(delegate.getState('ble_conn_ok'), isTrue);
      expect(delegate.getState('ble_read_val'), '01020304');
      expect(delegate.getState('ble_write_ok'), isTrue);
      expect(delegate.writtenBleCharValue, 'FFEE');

      // 引擎关闭自动停止扫描
      bleEngine.close();
      expect(delegate.bluetoothScanning, isFalse);
    });

    test('DatabaseApi: 沙箱内纯 Dart 结构化 SQL 引擎执行与查询', () async {
      final tempDir = await Directory.systemTemp.createTemp('ptx_db_test_');
      final dbCtx = PluginContext(
        pluginId: 'db_test',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        rootDir: tempDir,
        grantedPermissions: {PluginPermission.database},
      );
      final dbEngine = LuaEngine(context: dbCtx, delegate: delegate);

      dbEngine.loadAndExecute('''
        -- 1. 创建表
        db.execute("CREATE TABLE users (id, name, score)", function(res)
          state.set("db_create_ok", res.ok)
        end)

        -- 2. 插入多条记录
        db.execute("INSERT INTO users (id, name, score) VALUES (?, ?, ?)", { 1, "Alice", 95 }, function(res)
          state.set("db_ins1_ok", res.ok)
        end)
        db.execute("INSERT INTO users (id, name, score) VALUES (?, ?, ?)", { 2, "Bob", 80 }, function(res)
          state.set("db_ins2_ok", res.ok)
        end)

        -- 3. 条件与排序查询
        db.query("SELECT * FROM users WHERE score = ? ORDER BY score DESC", { 95 }, function(res)
          state.set("db_query_ok", res.ok)
          state.set("db_query_err", res.error)
          if res.rows and res.rows[1] then
            state.set("db_query_name", res.rows[1].name)
          end
        end)

        -- 4. 更新记录
        db.execute("UPDATE users SET score = ? WHERE name = ?", { 100, "Alice" }, function(res)
          state.set("db_update_ok", res.ok)
        end)

        -- 5. 批量处理
        db.batch({
          "INSERT INTO users (id, name, score) VALUES (3, 'Charlie', 88)",
          "DELETE FROM users WHERE name = 'Bob'"
        }, function(res)
          state.set("db_batch_ok", res.ok)
        end)
      ''');

      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(delegate.getState('db_create_ok'), isTrue);
      expect(delegate.getState('db_ins1_ok'), isTrue);
      expect(delegate.getState('db_ins2_ok'), isTrue);
      expect(delegate.getState('db_query_ok'), isTrue);
      expect(delegate.getState('db_query_name'), 'Alice');
      expect(delegate.getState('db_update_ok'), isTrue);
      expect(delegate.getState('db_batch_ok'), isTrue);

      // 6. 测试增强 SQL: 多行注释清洗、字面量插入与 COUNT 统计、多条件过滤
      dbEngine.loadAndExecute('''
        local sql = [[
          /* 多行 SQL 注释 */
          -- 单行 SQL 注释
          SELECT COUNT(*) AS total FROM users WHERE score >= 88 AND name LIKE 'C%'
        ]]
        db.query(sql, {}, function(res)
          if res.ok and res.rows and res.rows[1] then
            state.set("db_count_val", res.rows[1].total)
          end
        end)
      ''');

      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(delegate.getState('db_count_val'), 1);

      dbEngine.close();
      await tempDir.delete(recursive: true);
    });

    test('AiApi: 统一大模型网关 chat 与 streamChat 调用', () async {
      // 1. 无权限拦截
      expect(
        () => engine.loadAndExecute('ai.chat({ messages = {} }, function() end)'),
        throwsException,
      );

      // 2. 有权限正常发起
      final aiCtx = PluginContext(
        pluginId: 'ai_test',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {PluginPermission.ai},
      );
      final aiEngine = LuaEngine(context: aiCtx, delegate: delegate);

      aiEngine.loadAndExecute('''
        ai.isAvailable(function(avail)
          state.set("ai_avail", avail)
        end)

        ai.chat({
          messages = { { role = "user", content = "Hello AI" } },
          model = "gpt-4o",
          temperature = 0.5
        }, function(res)
          state.set("ai_chat_ok", res.ok)
          state.set("ai_chat_text", res.text)
        end)

        local chunks = ""
        ai.streamChat({
          messages = { { role = "user", content = "Stream test" } }
        }, function(chunk)
          chunks = chunks .. chunk
        end, function()
          state.set("ai_stream_text", chunks)
        end)
      ''');

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(delegate.getState('ai_avail'), isTrue);
      expect(delegate.getState('ai_chat_ok'), isTrue);
      expect(delegate.getState('ai_chat_text'), 'AI generated response');
      expect(delegate.getState('ai_stream_text'), 'Chunk1 Chunk2');
    });

    test('IpcApi: 跨插件服务注册、RPC 调用与管道打开', () async {
      // 1. 无权限拦截
      expect(
        () => engine.loadAndExecute('plugin.call("other", "fn")'),
        throwsException,
      );

      // 2. 提供者插件 (provider) 注册接口
      final providerCtx = PluginContext(
        pluginId: 'provider_plugin',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {PluginPermission.ipc},
      );
      final providerEngine = LuaEngine(context: providerCtx, delegate: delegate);

      providerEngine.loadAndExecute('''
        plugin.export("doubleNumber", function(num)
          return num * 2
        end)
      ''');

      // 3. 调用者插件 (caller) 进行 RPC 调用
      final callerCtx = PluginContext(
        pluginId: 'caller_plugin',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {PluginPermission.ipc},
      );
      final callerEngine = LuaEngine(context: callerCtx, delegate: delegate);

      callerEngine.loadAndExecute('''
        plugin.call("provider_plugin", "doubleNumber", 21, function(res)
          state.set("ipc_call_ok", res.ok)
          state.set("ipc_call_val", res.result)
        end)

        plugin.open("diff_tool", { initialText = "compare me" }, function(res)
          state.set("ipc_open_ok", res.ok)
        end)
      ''');

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(delegate.getState('ipc_call_ok'), isTrue);
      expect(delegate.getState('ipc_call_val'), 42);
      expect(delegate.getState('ipc_open_ok'), isTrue);
      expect(delegate.openedPluginId, 'diff_tool');
      expect(delegate.openedPluginData?['initialText'], 'compare me');

      // 关闭 provider 引擎后，其接口被自动注销
      providerEngine.close();
      expect(
        PluginIpcBroker.instance.hasService('provider_plugin', 'doubleNumber'),
        isFalse,
      );
    });

    test('VisionApi.recognizeText 离线 OCR 与 SystemApi.getInitialShare 初始分享', () async {
      final tempDir = await Directory.systemTemp.createTemp('ptx_ocr_test_');
      final ocrCtx = PluginContext(
        pluginId: 'ocr_test',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        rootDir: tempDir,
        grantedPermissions: {PluginPermission.photoLibrary, PluginPermission.storage},
      );
      final ocrEngine = LuaEngine(context: ocrCtx, delegate: delegate);

      // 1. 路径穿越拦截
      expect(
        () => ocrEngine.loadAndExecute('vision.recognizeText("../../secret.png")'),
        throwsException,
      );

      // 2. 正常沙箱 OCR 调用
      ocrEngine.loadAndExecute('''
        vision.recognizeText("doc.png", function(res)
          state.set("ocr_ok", res.ok)
          state.set("ocr_text", res.text)
        end)
        system.getInitialShare(function(share)
          state.set("initial_share_text", share.text)
        end)
      ''');

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(delegate.getState('ocr_ok'), isTrue);
      expect(delegate.getState('ocr_text'), 'Recognized Sample Text');
      expect(delegate.getState('initial_share_text'), 'shared content');

      ocrEngine.close();
      await tempDir.delete(recursive: true);
    });
  });
}

