import 'package:lua_dardo/lua.dart';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';
import 'package:plugin_toolbox_lua/plugin_toolbox_lua.dart';
import 'package:plugin_toolbox_lua/src/api/yaml_parser.dart';

import 'helpers/lua_test_helpers.dart';

class DefaultUiDelegate extends LuaUiDelegate {
  @override
  void showToast(String message) {}
  @override
  Future<void> showAlert(String title, String message) async {}
  @override
  Future<bool> showConfirm(String title, String message) async => false;
}

class DefaultMediaDelegate extends LuaMediaDelegate {}

class DefaultDeviceDelegate extends LuaDeviceDelegate {}

class DefaultAiDelegate extends LuaAiDelegate {}

class DefaultClipboardDelegate extends LuaClipboardDelegate {}

class MemoryStateDelegate implements LuaStateDelegate {
  final Map<String, dynamic> state = {};
  @override
  void onStateChanged(String key, dynamic value) => state[key] = value;
  @override
  dynamic getState(String key) => state[key];
  @override
  Map<String, dynamic> getAllStates() => Map.unmodifiable(state);
}

class _TestDialogUiDelegate extends LuaUiDelegate {
  final void Function(String)? onToast;
  final Future<void> Function(String, String)? onAlert;
  _TestDialogUiDelegate({this.onToast, this.onAlert});

  @override
  void showToast(String message) => onToast?.call(message);

  @override
  Future<void> showAlert(String title, String message) async {
    await onAlert?.call(title, message);
  }

  @override
  Future<bool> showConfirm(String title, String message) async => false;
}

void main() {
  group('DomainDelegates 默认实现契约断言 (覆盖默认兜底路径)', () {
    test('LuaUiDelegate 默认抽象方法全部返回预期的默认值与安全空值', () async {
      final ui = DefaultUiDelegate();
      ui.showToast('toast');
      await ui.showAlert('title', 'msg');
      expect(await ui.showConfirm('title', 'msg'), isFalse);
      expect(ui.hideKeyboard, returnsNormally);
      expect(await ui.pickDate(), isNull);
      expect(await ui.pickTime(), isNull);
      expect(await ui.showPrompt(title: 't'), isNull);
      expect(await ui.showPickItem(title: 't', items: ['a', 'b']), isNull);
      expect(await ui.showBottomSheet(title: 't', items: ['a', 'b']), isNull);
    });

    test('LuaMediaDelegate 默认方法返回预期的空值与 false', () async {
      final media = DefaultMediaDelegate();
      expect(await media.pickFile(), isNull);
      expect(await media.pickImage(), isNull);
      expect(await media.saveToGallery('test.png'), isFalse);
      expect(await media.exportFile('test.png'), isFalse);
      expect(await media.scanBarcode(), isNull);
      expect(await media.decodeBarcodeFromImage('test.png'), isNull);
      expect(await media.imageInfo('test.png'), isNull);
      expect(await media.compressImage('s', 'd'), isFalse);
      expect(await media.cropImage('s', 'd', x: 0, y: 0, width: 10, height: 10),
          isFalse);
      expect(await media.convertImage('s', 'd', format: 'jpg'), isFalse);
      expect(await media.stripExifImage('s', 'd'), isFalse);
      expect(await media.playAudio('a.mp3'), isFalse);
      expect(await media.stopAudio(), isFalse);
      expect(await media.playTone(440.0, 100), isFalse);
      expect(await media.startAudioRecording('r.m4a'), isFalse);
      expect(await media.stopAudioRecording(), isNull);
      expect(await media.getAudioDecibel(), 0.0);
      expect(await media.speakText('hello'), isFalse);
      expect(await media.stopSpeaking(), isFalse);
      expect(await media.recognizeText('img.png'), isNull);
      expect(await media.takePhoto(), isNull);
      expect(await media.captureScreen(destPath: 'shot.png'), isFalse);
    });

    test('LuaDeviceDelegate 默认方法与属性全部返回默认安全状态', () async {
      final dev = DefaultDeviceDelegate();
      expect(() => dev.hapticFeedback('light'), returnsNormally);
      await dev.shareText('text');
      expect(await dev.openUrl('https://example.com'), isFalse);
      expect(await dev.setTorch(true), isFalse);
      expect(dev.isTorchOn, isFalse);
      expect(await dev.shareFile('f.txt'), isFalse);
      expect(await dev.startSensor('accel'), isFalse);
      expect(await dev.stopSensor('accel'), isFalse);
      expect(await dev.getSensorData('accel'), isNull);
      expect(await dev.showNotification(title: 't', body: 'b'), -1);
      expect(
          await dev.scheduleNotification(
              title: 't', body: 'b', delaySeconds: 1),
          -1);
      expect(await dev.cancelNotification(1), isFalse);
      expect(await dev.cancelAllNotifications(), isFalse);
      expect(dev.batteryLevel, 100);
      expect(dev.isCharging, isFalse);
      expect(dev.networkType, 'unknown');
      expect(await dev.getBatteryLevel(), 100);
      expect(await dev.checkIsCharging(), isFalse);
      expect(await dev.fetchNetworkType(), 'unknown');
      expect(await dev.isBiometricsAvailable(), isFalse);
      expect(await dev.authenticateBiometrics(),
          {'success': false, 'error': 'not_supported'});
      expect(await dev.setKeepScreenOn(true), isFalse);
      expect(await dev.setBrightness(0.5), isFalse);
      expect(await dev.getBrightness(), 1.0);
      expect(await dev.resetBrightness(), isFalse);
      expect(await dev.getInitialShare(), isNull);
      expect(await dev.isLocationAvailable(), isFalse);
      expect(await dev.getCurrentPosition(), isNull);
      expect(await dev.isNfcAvailable(), isFalse);
      expect(await dev.readNdef(), isNull);
      expect(await dev.writeNdef([]), isFalse);
      expect(await dev.isBluetoothAvailable(), isFalse);
      expect(await dev.startBluetoothScan((_) {}), isFalse);
      expect(await dev.stopBluetoothScan(), isFalse);
      expect(await dev.connectBluetooth('id'), isFalse);
      expect(await dev.disconnectBluetooth('id'), isFalse);
      expect(await dev.readBluetoothCharacteristic('id', 's', 'c'), isNull);
      expect(
          await dev.writeBluetoothCharacteristic('id', 's', 'c', 'v'), isFalse);
      expect(await dev.openPlugin('other'), isFalse);
      expect(await dev.getWifiInfo(), isNull);
      final ping = await dev.pingHost('127.0.0.1');
      expect(ping['ok'], isFalse);
    });

    test('LuaAiDelegate 与 LuaClipboardDelegate 默认实现契约', () async {
      final ai = DefaultAiDelegate();
      expect(await ai.isAiAvailable(), isFalse);
      final chat = await ai.aiChat(messages: []);
      expect(chat['ok'], isFalse);
      expect(await ai.aiStreamChat(messages: []).toList(), isEmpty);

      final clip = DefaultClipboardDelegate();
      clip.setClipboardText('copied');
      expect(await clip.getClipboardText(), isNull);
    });

    test('CompositeLuaHostDelegate 子委托为空时安全降级与有值时正确转发', () async {
      final state = MemoryStateDelegate();
      final composite = CompositeLuaHostDelegate(
        stateDelegate: state,
        uiDelegate: DefaultUiDelegate(),
        mediaDelegate: DefaultMediaDelegate(),
        deviceDelegate: DefaultDeviceDelegate(),
        aiDelegate: DefaultAiDelegate(),
        clipboardDelegate: DefaultClipboardDelegate(),
      );

      composite.onStateChanged('k', 'v');
      expect(composite.getState('k'), 'v');
      expect(composite.getAllStates()['k'], 'v');

      composite.showToast('test');
      expect(await composite.showConfirm('t', 'm'), isFalse);
      composite.hideKeyboard();
      expect(await composite.pickDate(), isNull);
      expect(await composite.pickTime(), isNull);
      expect(await composite.showPrompt(title: 't'), isNull);
      expect(await composite.showPickItem(title: 't', items: ['1']), isNull);
      expect(await composite.showBottomSheet(title: 't', items: ['1']), isNull);

      expect(await composite.pickFile(), isNull);
      expect(await composite.pickImage(), isNull);
      expect(await composite.saveToGallery('p'), isFalse);
      expect(await composite.exportFile('p'), isFalse);
      expect(await composite.scanBarcode(), isNull);
      expect(await composite.decodeBarcodeFromImage('p'), isNull);
      expect(await composite.imageInfo('p'), isNull);
      expect(await composite.compressImage('s', 'd'), isFalse);
      expect(
          await composite.cropImage('s', 'd', x: 0, y: 0, width: 1, height: 1),
          isFalse);
      expect(await composite.convertImage('s', 'd', format: 'png'), isFalse);
      expect(await composite.stripExifImage('s', 'd'), isFalse);
      expect(await composite.playAudio('p'), isFalse);
      expect(await composite.stopAudio(), isFalse);
      expect(await composite.playTone(440, 100), isFalse);
      expect(await composite.startAudioRecording('p'), isFalse);
      expect(await composite.stopAudioRecording(), isNull);
      expect(await composite.getAudioDecibel(), 0.0);
      expect(await composite.speakText('t'), isFalse);
      expect(await composite.stopSpeaking(), isFalse);
      expect(await composite.recognizeText('p'), isNull);
      expect(await composite.takePhoto(), isNull);
      expect(await composite.captureScreen(destPath: 'p'), isFalse);

      composite.hapticFeedback('light');
      await composite.shareText('t');
      expect(await composite.openUrl('https://example.com'), isFalse);
      expect(await composite.setTorch(true), isFalse);
      expect(composite.isTorchOn, isFalse);
      expect(await composite.shareFile('p'), isFalse);
      expect(await composite.startSensor('s'), isFalse);
      expect(await composite.stopSensor('s'), isFalse);
      expect(await composite.getSensorData('s'), isNull);
      expect(await composite.showNotification(title: 't', body: 'b'), -1);
      expect(
          await composite.scheduleNotification(
              title: 't', body: 'b', delaySeconds: 1),
          -1);
      expect(await composite.cancelNotification(1), isFalse);
      expect(await composite.cancelAllNotifications(), isFalse);
      expect(composite.batteryLevel, 100);
      expect(composite.isCharging, isFalse);
      expect(composite.networkType, 'unknown');
      expect(await composite.getBatteryLevel(), 100);
      expect(await composite.checkIsCharging(), isFalse);
      expect(await composite.fetchNetworkType(), 'unknown');
      expect(await composite.isBiometricsAvailable(), isFalse);
      expect(await composite.authenticateBiometrics(),
          {'success': false, 'error': 'not_supported'});
      expect(await composite.setKeepScreenOn(true), isFalse);
      expect(await composite.setBrightness(0.5), isFalse);
      expect(await composite.getBrightness(), 1.0);
      expect(await composite.resetBrightness(), isFalse);
      expect(await composite.getInitialShare(), isNull);
      expect(await composite.isLocationAvailable(), isFalse);
      expect(await composite.getCurrentPosition(), isNull);
      expect(await composite.isNfcAvailable(), isFalse);
      expect(await composite.readNdef(), isNull);
      expect(await composite.writeNdef([]), isFalse);
      expect(await composite.isBluetoothAvailable(), isFalse);
      expect(await composite.startBluetoothScan((_) {}), isFalse);
      expect(await composite.stopBluetoothScan(), isFalse);
      expect(await composite.connectBluetooth('id'), isFalse);
      expect(await composite.disconnectBluetooth('id'), isFalse);
      expect(
          await composite.readBluetoothCharacteristic('id', 's', 'c'), isNull);
      expect(await composite.writeBluetoothCharacteristic('id', 's', 'c', 'v'),
          isFalse);
      expect(await composite.openPlugin('other'), isFalse);
      expect(await composite.getWifiInfo(), isNull);
      expect((await composite.pingHost('host'))['ok'], isFalse);

      expect(await composite.isAiAvailable(), isFalse);
      expect((await composite.aiChat(messages: []))['ok'], isFalse);
      expect(await composite.aiStreamChat(messages: []).toList(), isEmpty);

      composite.setClipboardText('clip');
      expect(await composite.getClipboardText(), isNull);
    });
  });

  group('LuaPluginRunner 生命周期与异常保护', () {
    late Directory tempDir;
    late PluginContext context;
    late CompositeLuaHostDelegate delegate;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('ptx_runner_test_');
      delegate = CompositeLuaHostDelegate(stateDelegate: MemoryStateDelegate());
      context = PluginContext(
        pluginId: 'runner_plugin',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {},
        rootDir: tempDir,
      );
    });

    tearDown(() async {
      try {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      } catch (_) {}
    });

    test('插件 context 缺失时拒绝创建并抛出 StateError', () {
      final uninitPlugin = DynamicPlugin(
        manifest: const PluginManifest(
          id: 'uninit',
          name: 'Uninit',
          version: '1.0.0',
          description: '',
          author: '',
          type: 'lua',
          category: PluginCategory.other,
          permissions: [],
          entry: 'main.lua',
          ui: 'ui.json',
        ),
        rootDir: tempDir,
      );

      expect(
        () => LuaPluginRunner(plugin: uninitPlugin, delegate: delegate),
        throwsStateError,
      );
    });

    test('入口脚本不存在时 start 抛出 FileSystemException', () async {
      final plugin = DynamicPlugin(
        manifest: const PluginManifest(
          id: 'missing_entry',
          name: 'Missing',
          version: '1.0.0',
          description: '',
          author: '',
          type: 'lua',
          category: PluginCategory.other,
          permissions: [],
          entry: 'non_existent.lua',
          ui: 'ui.json',
        ),
        rootDir: tempDir,
      );
      await plugin.initialize(context);

      final runner = LuaPluginRunner(plugin: plugin, delegate: delegate);
      expect(() => runner.start(), throwsA(isA<FileSystemException>()));
    });

    test('正常加载脚本并调度 onResume, onPause 与 onDispose 生命周期', () async {
      final entryFile = File('${tempDir.path}/main.lua');
      await entryFile.writeAsString('''
        function onInit()
          state.set("inited", true)
        end
        function onResume()
          state.set("resumed", true)
        end
        function onPause()
          state.set("paused", true)
        end
        function onDispose()
          state.set("disposed", true)
        end
        function doCustomAction(val)
          state.set("action_val", val)
        end
      ''');

      final plugin = DynamicPlugin(
        manifest: const PluginManifest(
          id: 'lifecycle_plugin',
          name: 'Lifecycle',
          version: '1.0.0',
          description: '',
          author: '',
          type: 'lua',
          category: PluginCategory.other,
          permissions: [],
          entry: 'main.lua',
          ui: 'ui.json',
        ),
        rootDir: tempDir,
      );
      await plugin.initialize(context);

      final runner = LuaPluginRunner(plugin: plugin, delegate: delegate);
      await runner.start();
      expect(delegate.getState('inited'), isTrue);

      runner.onResume();
      expect(delegate.getState('resumed'), isTrue);

      runner.onPause();
      expect(delegate.getState('paused'), isTrue);

      runner.dispatchAction('doCustomAction', ['hello_runner']);
      expect(delegate.getState('action_val'), 'hello_runner');

      runner.dispose();
      expect(delegate.getState('disposed'), isTrue);
    });

    test('ApiGuard 及各枚举转换分支覆盖', () {
      expect(HapticType.from('light'), HapticType.light);
      expect(HapticType.from('medium'), HapticType.medium);
      expect(HapticType.from('heavy'), HapticType.heavy);
      expect(HapticType.from('selection'), HapticType.selection);
      expect(HapticType.from('vibrate'), HapticType.vibrate);
      expect(HapticType.from('unknown'), HapticType.vibrate);
      expect(HapticType.from(null), HapticType.vibrate);

      expect(SensorCategory.tryParse('accelerometer'),
          SensorCategory.accelerometer);
      expect(SensorCategory.tryParse('gyroscope'), SensorCategory.gyroscope);
      expect(
          SensorCategory.tryParse('magnetometer'), SensorCategory.magnetometer);
      expect(SensorCategory.tryParse('useraccelerometer'),
          SensorCategory.userAccelerometer);
      expect(SensorCategory.tryParse('all'), SensorCategory.all);
      expect(SensorCategory.tryParse('unknown'), isNull);
      expect(SensorCategory.tryParse(null), isNull);

      expect(HashType.tryParse('md5'), HashType.md5);
      expect(HashType.tryParse('sha1'), HashType.sha1);
      expect(HashType.tryParse('sha256'), HashType.sha256);
      expect(HashType.tryParse('sha512'), HashType.sha512);
      expect(HashType.tryParse('crc32'), HashType.crc32);
      expect(HashType.tryParse('unknown'), isNull);
      expect(HashType.tryParse(null), isNull);
    });

    test('YamlParser 解析与序列化全功能覆盖', () {
      expect(YamlParser.parse(''), isNull);
      expect(YamlParser.parse('# 仅注释\n  # 缩进注释'), isNull);
      expect(YamlParser.parse('   \n  \n'), isNull);

      expect(YamlParser.parse('true'), isTrue);
      expect(YamlParser.parse('False'), isFalse);
      expect(YamlParser.parse('null'), isNull);
      expect(YamlParser.parse('~'), isNull);
      expect(YamlParser.parse('12345'), 12345);
      expect(YamlParser.parse('3.1415'), 3.1415);
      expect(YamlParser.parse('"hello world"'), 'hello world');
      expect(YamlParser.parse("'single quote'"), 'single quote');

      const yamlText = '''
# 配置文件
app: toolbox # 内联注释
version: 1.0 # 版本号
port: 8080
enabled: true
meta:
  author: "developer"
  license: MIT
items:
  - apple
  - banana
  - name: orange
    count: 5
''';
      final parsed = YamlParser.parse(yamlText);
      expect(parsed, isA<Map>());
      expect(parsed['app'], 'toolbox');
      expect(parsed['version'], 1.0);
      expect(parsed['port'], 8080);
      expect(parsed['enabled'], isTrue);
      expect(parsed['meta']['author'], 'developer');
      expect(parsed['meta']['license'], 'MIT');
      expect(parsed['items'], isA<List>());
      expect(parsed['items'][0], 'apple');
      expect(parsed['items'][1], 'banana');
      expect(parsed['items'][2]['name'], 'orange');
      expect(parsed['items'][2]['count'], 5);

      const listYaml = '''
- first
- second
-
  third_sub: 100
''';
      final parsedList = YamlParser.parse(listYaml);
      expect(parsedList, isA<List>());
      expect(parsedList[0], 'first');
      expect(parsedList[1], 'second');
      expect(parsedList[2]['third_sub'], 100);

      final serialized = YamlParser.stringify({
        'name': 'demo',
        'url': 'http://example.com',
        'active': false,
        'count': 3,
        'info': {'desc': 'test'},
        'tags': [
          'a',
          'b',
          {'tag_id': 1}
        ],
      });
      expect(serialized.contains('name: demo'), isTrue);
      expect(serialized.contains('url: "http://example.com"'), isTrue);
      expect(serialized.contains('active: false'), isTrue);
      expect(serialized.contains('count: 3'), isTrue);
      expect(serialized.contains('info:'), isTrue);
      expect(serialized.contains('tags:'), isTrue);
    });

    test('NetworkApi 私有/本地地址与 SSRF 白名单防御机制覆盖', () async {
      expect(NetworkApi.isPrivateOrLocalHost('localhost'), isTrue);
      expect(NetworkApi.isPrivateOrLocalHost('app.localhost'), isTrue);
      expect(NetworkApi.isPrivateOrLocalHost('test.local'), isTrue);
      expect(NetworkApi.isPrivateOrLocalHost('service.internal'), isTrue);
      expect(NetworkApi.isPrivateOrLocalHost('gateway.lan'), isTrue);
      expect(NetworkApi.isPrivateOrLocalHost(''), isFalse);
      expect(NetworkApi.isPrivateOrLocalHost('google.com'), isFalse);
      expect(NetworkApi.isPrivateOrLocalHost('127.0.0.1'), isTrue);
      expect(NetworkApi.isPrivateOrLocalHost('10.0.0.1'), isTrue);
      expect(NetworkApi.isPrivateOrLocalHost('0.0.0.0'), isTrue);
      expect(NetworkApi.isPrivateOrLocalHost('169.254.1.1'), isTrue);
      expect(NetworkApi.isPrivateOrLocalHost('172.16.0.1'), isTrue);
      expect(NetworkApi.isPrivateOrLocalHost('172.31.255.255'), isTrue);
      expect(NetworkApi.isPrivateOrLocalHost('172.32.0.1'), isFalse);
      expect(NetworkApi.isPrivateOrLocalHost('192.168.1.1'), isTrue);
      expect(NetworkApi.isPrivateOrLocalHost('255.255.255.255'), isTrue);
      expect(NetworkApi.isPrivateOrLocalHost('8.8.8.8'), isFalse);
      expect(NetworkApi.isPrivateOrLocalHost('[::1]'), isTrue);
      expect(NetworkApi.isPrivateOrLocalHost('::1'), isTrue);
      expect(NetworkApi.isPrivateOrLocalHost('fc00::1'), isTrue);
      expect(NetworkApi.isPrivateOrLocalHost('fd12::1'), isTrue);
      expect(NetworkApi.isPrivateOrLocalHost('::ffff:127.0.0.1'), isTrue);
      expect(NetworkApi.isPrivateOrLocalHost('::ffff:192.168.1.1'), isTrue);
      expect(NetworkApi.isPrivateOrLocalHost('::ffff:8.8.8.8'), isFalse);
      expect(NetworkApi.isPrivateOrLocalHost('localhost:8080'), isTrue);
      expect(NetworkApi.isPrivateOrLocalHost('example.com:8080'), isFalse);

      final ctxNoWhitelist = PluginContext(
        pluginId: 'test_plugin',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {PluginPermission.network},
      );
      expect(NetworkApi.isHostAllowedWithSsrfCheck(ctxNoWhitelist, '127.0.0.1'),
          isFalse);
      expect(
          NetworkApi.isHostAllowedWithSsrfCheck(ctxNoWhitelist, 'google.com'),
          isTrue);

      final ctxStar = PluginContext(
        pluginId: 'test_plugin',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {PluginPermission.network},
        allowedDomains: ['*'],
      );
      expect(
          NetworkApi.isHostAllowedWithSsrfCheck(ctxStar, '127.0.0.1'), isFalse);
      expect(NetworkApi.isHostAllowedWithSsrfCheck(ctxStar, 'api.example.com'),
          isTrue);

      final ctxExplicit = PluginContext(
        pluginId: 'test_plugin',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {PluginPermission.network},
        allowedDomains: ['127.0.0.1'],
      );
      expect(NetworkApi.isHostAllowedWithSsrfCheck(ctxExplicit, '127.0.0.1'),
          isTrue);

      final originalDns = NetworkApi.dnsLookup;
      addTearDown(() => NetworkApi.dnsLookup = originalDns);

      NetworkApi.dnsLookup = (host) async => [InternetAddress('127.0.0.1')];
      expect(
          await NetworkApi.checkDnsResolutionSafety(ctxStar, 'rebinding.test'),
          isFalse);

      NetworkApi.dnsLookup = (host) async => [InternetAddress('93.184.216.34')];
      expect(await NetworkApi.checkDnsResolutionSafety(ctxStar, 'example.com'),
          isTrue);

      NetworkApi.dnsLookup = (host) async => [];
      expect(
          await NetworkApi.checkDnsResolutionSafety(ctxStar, 'notfound.test'),
          isFalse);

      NetworkApi.dnsLookup = (host) async => throw Exception('DNS error');
      expect(await NetworkApi.checkDnsResolutionSafety(ctxStar, 'error.test'),
          isFalse);
    });

    test('ApiGuard.checkPermission 与 checkAnyPermission 静态断言', () {
      final ls = LuaState.newState();
      final ctxWithStorage = PluginContext(
        pluginId: 'test',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {PluginPermission.storage},
      );
      expect(
        () => ApiGuard.checkPermission(
            ls, ctxWithStorage, PluginPermission.storage),
        returnsNormally,
      );
      expect(
        () => ApiGuard.checkAnyPermission(ls, ctxWithStorage,
            [PluginPermission.storage, PluginPermission.network]),
        returnsNormally,
      );
      expect(
        () => ApiGuard.checkPermission(
            ls, ctxWithStorage, PluginPermission.network),
        throwsA(anything),
      );
      expect(
        () => ApiGuard.checkAnyPermission(ls, ctxWithStorage,
            [PluginPermission.network, PluginPermission.bluetooth]),
        throwsA(anything),
      );
    });

    test('LuaEngine 基础状态与生命周期属性', () {
      final engine = LuaEngine(context: context, delegate: delegate);
      expect(engine.isClosed, isFalse);
      expect(engine.allocatedBytes, greaterThanOrEqualTo(0));
      expect(engine.disposables, isNotNull);
      engine.close();
      expect(engine.isClosed, isTrue);
    });

    test('dialog API 绑定调用触发 delegate 对应方法', () async {
      String? toastMsg;
      String? alertTitle;
      String? alertMsg;
      final customUi = _TestDialogUiDelegate(
        onToast: (m) => toastMsg = m,
        onAlert: (t, m) async {
          alertTitle = t;
          alertMsg = m;
        },
      );
      final composite = CompositeLuaHostDelegate(
        stateDelegate: delegate,
        uiDelegate: customUi,
      );
      final engine = LuaEngine(context: context, delegate: composite);
      engine.loadAndExecute('''
        dialog.toast("hello toast")
        dialog.alert("alert title", "alert body")
      ''');
      expect(toastMsg, 'hello toast');
      expect(alertTitle, 'alert title');
      expect(alertMsg, 'alert body');
      engine.close();
    });
  });
}
