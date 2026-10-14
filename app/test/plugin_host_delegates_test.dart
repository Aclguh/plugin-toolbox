import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_toolbox/src/plugin_host/dynamic_plugin_host_page.dart';
import 'package:plugin_toolbox/src/plugin_host/plugin_host_ai_delegate.dart';
import 'package:plugin_toolbox/src/plugin_host/plugin_host_media_delegate.dart';
import 'package:plugin_toolbox/src/plugin_host/plugin_host_system_delegate.dart';
import 'package:plugin_toolbox/src/plugin_host/plugin_native_bridge.dart';
import 'package:plugin_toolbox/src/providers/app_providers.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TestHostDelegates
    with
        PluginHostAiDelegate,
        PluginHostSystemDelegate,
        PluginHostMediaDelegate {
  @override
  final PluginNativeBridge nativeBridge;

  TestHostDelegates(this.nativeBridge);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late PluginNativeBridge bridge;
  late TestHostDelegates hostDelegates;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    tempDir = Directory.systemTemp.createTempSync('host_delegates_test_');
    bridge = PluginNativeBridge(
      pluginRootDir: tempDir,
      storageQuotaMb: 10,
    );
    hostDelegates = TestHostDelegates(bridge);
  });

  tearDown(() {
    bridge.dispose();
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('PluginHostAiDelegate 正确转发至 nativeBridge', () async {
    final available = await hostDelegates.isAiAvailable();
    expect(available, isFalse);

    final chatRes = await hostDelegates.aiChat(messages: [
      {'role': 'user', 'content': 'hi'}
    ]);
    expect(chatRes['ok'], isFalse);

    expect(
      () => hostDelegates.aiStreamChat(messages: [
        {'role': 'user', 'content': 'hi'}
      ]).toList(),
      throwsA(isA<UnimplementedError>()),
    );
  });

  test('PluginHostMediaDelegate 正确转发至 nativeBridge', () async {
    expect(await hostDelegates.shareFile('non_exist.txt'), isFalse);
    expect(await hostDelegates.saveToGallery('pic.png'), isFalse);
    expect(await hostDelegates.exportFile('doc.pdf'), isFalse);
    expect(await hostDelegates.imageInfo('none.jpg'), isNull);
    expect(
      await hostDelegates.compressImage('src.png', 'dest.png'),
      isFalse,
    );
    expect(
      await hostDelegates.cropImage('src.png', 'dest.png',
          x: 0, y: 0, width: 10, height: 10),
      isFalse,
    );
    expect(
      await hostDelegates.convertImage('src.png', 'dest.jpg', format: 'jpeg'),
      isFalse,
    );
    expect(await hostDelegates.stripExifImage('src.jpg', 'dest.jpg'), isFalse);
    expect(await hostDelegates.playAudio('sound.mp3'), isFalse);
    expect(await hostDelegates.stopAudio(), isFalse);
    expect(await hostDelegates.playTone(440, 100), isFalse);
    expect(await hostDelegates.startAudioRecording('rec.m4a'), isFalse);
    expect(await hostDelegates.stopAudioRecording(), isNull);
    expect(await hostDelegates.getAudioDecibel(), 0.0);
    expect(await hostDelegates.speakText('hello'), isFalse);
    expect(await hostDelegates.stopSpeaking(), isFalse);
    expect(await hostDelegates.recognizeText('ocr.png'), isNull);
  });

  test('PluginHostSystemDelegate 正确转发至 nativeBridge', () async {
    expect(await hostDelegates.openUrl('https://example.com'), isFalse);
    expect(await hostDelegates.setTorch(true), isFalse);
    expect(hostDelegates.isTorchOn, isFalse);
    expect(await hostDelegates.startSensor('accelerometer'), isFalse);
    expect(await hostDelegates.stopSensor('accelerometer'), isFalse);
    expect(await hostDelegates.getSensorData('accelerometer'), isNull);
    expect(
      await hostDelegates.showNotification(title: 'T', body: 'B'),
      -1,
    );
    expect(
      await hostDelegates.scheduleNotification(
          title: 'T', body: 'B', delaySeconds: 5),
      -1,
    );
    expect(await hostDelegates.cancelNotification(1), isFalse);
    expect(await hostDelegates.cancelAllNotifications(), isFalse);
    expect(await hostDelegates.getBatteryLevel(), -1);
    expect(
      () => hostDelegates.checkIsCharging(),
      throwsA(isA<UnimplementedError>()),
    );
    expect(await hostDelegates.fetchNetworkType(), 'unknown');
    expect(await hostDelegates.isBiometricsAvailable(), isFalse);
    final bioAuth = await hostDelegates.authenticateBiometrics();
    expect(bioAuth['success'], isFalse);
    expect(await hostDelegates.setKeepScreenOn(true), isFalse);
    expect(await hostDelegates.setBrightness(0.5), isFalse);
    expect(await hostDelegates.getBrightness(), 1.0);
    expect(await hostDelegates.resetBrightness(), isFalse);
  });

  testWidgets('DynamicPluginHostPage 加载异常时渲染错误界面',
      (WidgetTester tester) async {
    final brokenPlugin = DynamicPlugin(
      manifest: const PluginManifest(
        id: 'broken_plugin',
        name: '损坏插件',
        version: '1.0.0',
        description: '测试损坏插件错误渲染态',
        author: 'Tester',
        type: 'lua',
        category: PluginCategory.system,
        permissions: [],
        entry: 'entry.lua',
        ui: 'ui/non_existent.json',
      ),
      rootDir: tempDir,
    );

    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: DynamicPluginHostPage(plugin: brokenPlugin),
        ),
      ),
    );

    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();

    // 验证错误提示
    expect(find.text('损坏插件'), findsOneWidget);
    expect(find.textContaining('插件运行错误'), findsOneWidget);
  });

  testWidgets('DynamicPluginHostPage 容器生命周期事件调度',
      (WidgetTester tester) async {
    final mockPlugin = DynamicPlugin(
      manifest: const PluginManifest(
        id: 'lifecycle_test',
        name: '生命周期测试',
        version: '1.0.0',
        description: '测试容器生命周期监听',
        author: 'Tester',
        type: 'lua',
        category: PluginCategory.calculator,
        permissions: [],
        entry: 'main.lua',
        ui: 'ui/main.ui.json',
      ),
      rootDir: tempDir,
    );

    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
    ]);
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: DynamicPluginHostPage(plugin: mockPlugin),
        ),
      ),
    );

    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();

    expect(find.text('生命周期测试'), findsOneWidget);

    // 触发前后台生命周期切换
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
  });
}
