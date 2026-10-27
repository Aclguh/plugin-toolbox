import 'package:flutter_test/flutter_test.dart';
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
  bool get isHeadless => false;

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

  String? clipboardContent;

  @override
  void setClipboardText(String text) {
    clipboardContent = text;
  }

  @override
  Future<String?> getClipboardText() async => clipboardContent;

  @override
  ({int width, int height, double pixelRatio}) getScreenMetrics() =>
      (width: 1080, height: 2400, pixelRatio: 2.0);

  @override
  String getSystemLocale() => 'zh_CN';

  @override
  String getSystemBrightness() => 'light';

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
  String? mockTakePhotoPath = 'camera/mock_photo.jpg';

  @override
  Future<String?> takePhoto({
    String? destPath,
    int quality = 90,
    String lensDirection = 'back',
  }) async =>
      mockTakePhotoPath;

  bool mockCaptureScreenResult = true;
  @override
  Future<bool> captureScreen({
    required String destPath,
    String? targetRef,
  }) async =>
      mockCaptureScreenResult;

  Map<String, dynamic>? mockWifiInfo = {
    'ssid': 'Toolbox-WiFi',
    'bssid': '00:11:22:33:44:55',
    'rssi': -55,
    'ip': '192.168.1.100',
  };
  @override
  Future<Map<String, dynamic>?> getWifiInfo() async => mockWifiInfo;

  @override
  Future<Map<String, dynamic>> pingHost(String host,
          {int timeoutMs = 3000}) async =>
      {'ok': true, 'host': host, 'reachable': true, 'latencyMs': 12};
  final Map<String, Map<String, dynamic>> mockSensors = {
    'accelerometer': {'x': 1.0, 'y': 2.0, 'z': 9.8},
    'gyroscope': {'x': 0.1, 'y': 0.2, 'z': 0.3},
    'compass': {'heading': 180.0},
    'light': {'lux': 450.0},
    'barometer': {'pressure': 1013.25},
  };
  final List<String> startedSensors = [];
  final List<String> stoppedSensors = [];

  @override
  Future<String?> scanBarcode({String? prompt}) async => mockScannedCode;

  @override
  Future<String?> decodeBarcodeFromImage(String filePath) async =>
      mockDecodedCode;

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
  Future<List<String>?> getStringList(String key) async =>
      _data[key] as List<String>?;

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

  @override
  Future<dynamic> getValue(String key) async => _data[key];

  @override
  Future<bool> setValue(String key, dynamic value) async {
    _data[key] = value;
    return true;
  }

  @override
  Future<dynamic> get(String key) => getValue(key);

  @override
  Future<bool> set(String key, dynamic value) => setValue(key, value);

  @override
  Future<bool> flush() async => true;
}

Future<void> waitForCondition(
  bool Function() condition, {
  int maxTries = 40,
  int stepMs = 25,
}) async {
  for (var i = 0; i < maxTries; i++) {
    if (condition()) return;
    await Future<void>.delayed(Duration(milliseconds: stepMs));
  }
}
