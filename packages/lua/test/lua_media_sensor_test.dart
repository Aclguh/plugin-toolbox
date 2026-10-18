import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';
import 'package:plugin_toolbox_lua/plugin_toolbox_lua.dart';

import 'helpers/lua_test_helpers.dart';

Future<void> _waitFor(
  bool Function() condition, {
  int maxTries = 40,
  int stepMs = 25,
}) =>
    waitForCondition(condition, maxTries: maxTries, stepMs: stepMs);

void main() {
  group('Lua Media, Sensor & Device APIs', () {
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
        grantedPermissions: {
          PluginPermission.clipboard,
          PluginPermission.storage,
        },
      );
      engine = LuaEngine(context: context, delegate: delegate);
    });

    tearDown(() {
      engine.close();
    });

    test('HapticApi 触觉反馈调用委派给宿主', () {
      engine.loadAndExecute('''
        haptic.light()
        haptic.medium()
        haptic.heavy()
        haptic.selection()
        haptic.vibrate()
      ''');
      expect(delegate.haptics,
          ['light', 'medium', 'heavy', 'selection', 'vibrate']);
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
        grantedPermissions: {
          PluginPermission.photoLibrary,
          PluginPermission.storage
        },
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
      expect(
          delegate.getState('scanned_via_cb'), 'https://example.com/mock-qr');

      // 默认状态写入方式
      camEngine.loadAndExecute('camera.scan()');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(
          delegate.getState('__scanned_code'), 'https://example.com/mock-qr');
    });

    test('CameraApi: takePhoto 拍照保存至沙箱与权限控制', () async {
      final tempDir = Directory.systemTemp.createTempSync('ptx_photo_test_');
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      final camCtx = PluginContext(
        pluginId: 'camera_photo_test',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {PluginPermission.camera, PluginPermission.storage},
        rootDir: tempDir,
      );
      final camEngine = LuaEngine(context: camCtx, delegate: delegate);

      camEngine.loadAndExecute('''
        camera.takePhoto({ quality = 85, lens = "front", destPath = "camera/mock_photo.jpg" }, function(path)
          state.set("photo_path", path)
        end)
      ''');
      await _waitFor(() => delegate.getState('photo_path') != null);
      expect(delegate.getState('photo_path'), 'camera/mock_photo.jpg');

      camEngine.close();
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
        () => visionEngine
            .loadAndExecute('vision.decodeBarcode("../../secret.png")'),
        throwsException,
      );
      expect(
        () => visionEngine
            .loadAndExecute('camera.decodeImage("../../secret.png")'),
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
        state.set("has_light", sensor.isAvailable("light"))
        state.set("has_baro", sensor.isAvailable("barometer"))
        state.set("has_foo", sensor.isAvailable("unknown_sensor"))
      ''');
      expect(delegate.getState('has_acc'), isTrue);
      expect(delegate.getState('has_gyro'), isTrue);
      expect(delegate.getState('has_comp'), isTrue);
      expect(delegate.getState('has_mag'), isTrue);
      expect(delegate.getState('has_light'), isTrue);
      expect(delegate.getState('has_baro'), isTrue);
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

      await _waitFor(() =>
          delegate.getState('bio_avail') != null &&
          delegate.getState('bio_success') != null);
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

      await _waitFor(() =>
          delegate.getState('rec_started') != null &&
          delegate.getState('rec_db') != null &&
          delegate.getState('rec_stopped') != null);
      expect(delegate.getState('rec_started'), isTrue);
      expect(delegate.getState('rec_db'), 65.5);
      expect(delegate.getState('rec_stopped'), isTrue);
      expect(delegate.getState('rec_path'), contains('rec.m4a'));

      audioEngine.close();
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

      await _waitFor(() =>
          delegate.getState('screen_on_ok') != null &&
          delegate.getState('brightness_set_ok') != null);
      expect(delegate.keepScreenOn, isTrue);
      expect(delegate.screenBrightness, 0.75);
      expect(delegate.getState('screen_on_ok'), isTrue);
      expect(delegate.getState('brightness_set_ok'), isTrue);

      // close 还原状态
      screenEngine.close();
      expect(delegate.keepScreenOn, isFalse);
      expect(delegate.brightnessReset, isTrue);
    });

    test('ScreenApi: capture 截图保存至沙箱与权限控制', () async {
      final tempDir = Directory.systemTemp.createTempSync('ptx_capture_test_');
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      final screenCtx = PluginContext(
        pluginId: 'screen_capture_test',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {PluginPermission.screen, PluginPermission.storage},
        rootDir: tempDir,
      );
      final screenEngine = LuaEngine(context: screenCtx, delegate: delegate);

      screenEngine.loadAndExecute('''
        screen.capture({ destPath = "captures/shot.png" }, function(path)
          state.set("capture_path", path)
        end)
      ''');

      await _waitFor(() => delegate.getState('capture_path') != null);
      expect(delegate.getState('capture_path'), 'captures/shot.png');

      screenEngine.close();
    });

    test('LocationApi: 权限控制与定位数据获取', () async {
      // 1. 无权限拦截
      expect(
        () => engine
            .loadAndExecute('location.getCurrentPosition(function() end)'),
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

      await _waitFor(() =>
          delegate.getState('loc_avail') != null &&
          delegate.getState('loc_ok') != null &&
          delegate.getState('loc_alt') != null);
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

      await _waitFor(() =>
          delegate.getState('nfc_avail') != null &&
          delegate.getState('nfc_read_ok') != null &&
          delegate.getState('nfc_write_ok') != null);
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

      await _waitFor(() =>
          delegate.getState('ble_scan_dev') != null &&
          delegate.getState('ble_conn_ok') != null &&
          delegate.getState('ble_read_val') != null &&
          delegate.getState('ble_write_ok') != null);
      expect(delegate.getState('ble_scan_dev'), 'Test Beacon');
      expect(delegate.getState('ble_conn_ok'), isTrue);
      expect(delegate.getState('ble_read_val'), '01020304');
      expect(delegate.getState('ble_write_ok'), isTrue);
      expect(delegate.writtenBleCharValue, 'FFEE');

      // 引擎关闭自动停止扫描
      bleEngine.close();
      expect(delegate.bluetoothScanning, isFalse);
    });

    test('VisionApi.recognizeText 离线 OCR 与 SystemApi.getInitialShare 初始分享',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('ptx_ocr_test_');
      final ocrCtx = PluginContext(
        pluginId: 'ocr_test',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        rootDir: tempDir,
        grantedPermissions: {
          PluginPermission.photoLibrary,
          PluginPermission.storage
        },
      );
      final ocrEngine = LuaEngine(context: ocrCtx, delegate: delegate);

      // 1. 路径穿越拦截
      expect(
        () => ocrEngine
            .loadAndExecute('vision.recognizeText("../../secret.png")'),
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

      await _waitFor(() =>
          delegate.getState('ocr_ok') != null &&
          delegate.getState('initial_share_text') != null);
      expect(delegate.getState('ocr_ok'), isTrue);
      expect(delegate.getState('ocr_text'), 'Recognized Sample Text');
      expect(delegate.getState('initial_share_text'), 'shared content');

      ocrEngine.close();
      await tempDir.delete(recursive: true);
    });
  });
}
