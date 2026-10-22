import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_toolbox/src/plugin_host/dynamic_plugin_host_page.dart';
import 'package:plugin_toolbox/src/plugin_host/plugin_host_ai_delegate.dart';
import 'package:plugin_toolbox/src/plugin_host/plugin_host_media_delegate.dart';
import 'package:plugin_toolbox/src/plugin_host/plugin_host_session.dart';
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

  testWidgets('DynamicPluginHostPage 加载异常时渲染错误界面', (WidgetTester tester) async {
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

  testWidgets('DynamicPluginHostPage 容器生命周期事件调度', (WidgetTester tester) async {
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

  test('PluginHostSession 会话状态流转与生命周期控制', () async {
    final uiDir = Directory('${tempDir.path}/ui')..createSync(recursive: true);
    final uiFile = File('${uiDir.path}/main.ui.json');
    uiFile.writeAsStringSync('{"type": "Center", "props": {"text": "hello"}}');
    final scriptFile = File('${tempDir.path}/main.lua');
    scriptFile.writeAsStringSync(
        'function onInit() end\nfunction onResume() end\nfunction onPause() end');

    final sessionPlugin = DynamicPlugin(
      manifest: const PluginManifest(
        id: 'session_test_p',
        name: '会话测试插件',
        version: '1.0.0',
        description: '测试纯 Dart 会话控制器',
        author: 'Tester',
        type: 'lua',
        category: PluginCategory.calculator,
        permissions: [],
        entry: 'main.lua',
        ui: 'ui/main.ui.json',
      ),
      rootDir: tempDir,
    );

    final session = PluginHostSession(plugin: sessionPlugin);
    expect(session.status, PluginSessionStatus.loading);
    expect(session.isLoading, isTrue);

    await session.start();
    expect(session.status, PluginSessionStatus.ready);
    expect(session.isReady, isTrue);
    expect(session.hasError, isFalse);
    expect(session.uiRootNode?['type'], 'Center');

    // 状态读写委托验证
    session.onStateChanged('msg', 'world');
    expect(session.getState('msg'), 'world');
    expect(session.getAllStates()['msg'], 'world');

    // 生命周期变迁验证
    session.handleAppLifecycleState(AppLifecycleState.paused);
    session.handleAppLifecycleState(AppLifecycleState.resumed);

    // 重新加载与销毁验证
    await session.reload();
    expect(session.isReady, isTrue);

    // 交互与剪贴板/震动覆盖
    session.callLua('onInit');
    session.setClipboardText('clipboard_data');
    await session.getClipboardText();
    session.hapticFeedback('light');
    session.hapticFeedback('medium');
    session.hapticFeedback('heavy');
    session.hapticFeedback('selection');
    session.hapticFeedback('vibrate');

    session.showToast('toast');
    await session.showAlert('title', 'msg');
    expect(await session.showConfirm('t', 'm'), isFalse);
    expect(await session.showPrompt(title: 't'), isNull);
    expect(await session.showPickItem(title: 't', items: ['a']), isNull);
    expect(await session.showBottomSheet(title: 't', items: ['a']), isNull);
    expect(await session.pickDate(), isNull);
    expect(await session.pickTime(), isNull);
    expect(await session.openPlugin('other'), isFalse);
    expect(await session.scanBarcode(), isNull);
    expect(await session.decodeBarcodeFromImage('img.png'), isNull);
    session.hideKeyboard();

    session.dispose();
  });

  testWidgets('DynamicPluginHostPage UI 交互协议契约', (tester) async {
    final entryFile = File('${tempDir.path}/entry.lua');
    entryFile.writeAsStringSync('function onInit() end');
    final uiFile = File('${tempDir.path}/ui.json');
    uiFile.writeAsStringSync('{"type": "Center", "props": {"text": "hello"}}');

    final dynamicPlugin = DynamicPlugin(
      manifest: const PluginManifest(
        id: 'ui_handler_test',
        name: 'UI协议测试',
        version: '1.0.0',
        description: '',
        author: '',
        type: 'lua',
        category: PluginCategory.other,
        permissions: [],
        entry: 'entry.lua',
        ui: 'ui.json',
      ),
      rootDir: tempDir,
    );

    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: MaterialApp(
          home: DynamicPluginHostPage(plugin: dynamicPlugin),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(DynamicPluginHostPage), findsOneWidget);
    final dynamic state = tester.state(find.byType(DynamicPluginHostPage));
    state.showToast('hello toast');
    await tester.pump();
    state.hideKeyboard();
    await tester.pump();
  });

  testWidgets('DynamicPluginHostPage 交互协议与生命周期调度', (tester) async {
    final entryFile = File('${tempDir.path}/entry2.lua');
    entryFile.writeAsStringSync('function onInit() end');
    final uiFile = File('${tempDir.path}/ui2.json');
    uiFile.writeAsStringSync('{"type": "Center", "props": {"text": "hello"}}');

    final dynamicPlugin = DynamicPlugin(
      manifest: const PluginManifest(
        id: 'ui_branch_test',
        name: 'UI分支测试',
        version: '1.0.0',
        description: '',
        author: '',
        type: 'lua',
        category: PluginCategory.other,
        permissions: [],
        entry: 'entry2.lua',
        ui: 'ui2.json',
      ),
      rootDir: tempDir,
    );

    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: MaterialApp(
          home: DynamicPluginHostPage(plugin: dynamicPlugin),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final dynamic state = tester.state(find.byType(DynamicPluginHostPage));

    // 测试生命周期派发
    state.didChangeAppLifecycleState(AppLifecycleState.paused);
    state.didChangeAppLifecycleState(AppLifecycleState.resumed);

    // 测试 openPlugin 容错
    expect(await state.openPlugin('non_exist_target'), isFalse);
  });

  testWidgets('DynamicPluginHostPage 异常态 ErrorView 点击重试触发重新加载', (tester) async {
    final brokenPlugin = DynamicPlugin(
      manifest: const PluginManifest(
        id: 'broken_plugin_retry',
        name: '崩溃测试插件',
        version: '1.0.0',
        description: '',
        author: '',
        type: 'lua',
        category: PluginCategory.other,
        permissions: [],
        entry: 'missing_entry.lua',
        ui: 'ui/non_existent.json',
      ),
      rootDir: tempDir,
    );

    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: MaterialApp(
          home: DynamicPluginHostPage(plugin: brokenPlugin),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('插件运行错误'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);

    await tester.tap(find.text('重试'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('插件运行错误'), findsOneWidget);
  });
}
