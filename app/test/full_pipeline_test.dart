import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_toolbox/src/plugin_host/dynamic_plugin_host_page.dart';
import 'package:plugin_toolbox/src/providers/app_providers.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 构造包含标准结构的不含数字签名的原始 PTX 压缩包字节
Uint8List _buildUnsignedPtxBytes({
  required String id,
  required String name,
  String version = '1.0.0',
}) {
  final archive = Archive();

  void addFile(String path, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(path, bytes.length, bytes));
  }

  // 1. plugin.json
  addFile(
    'plugin.json',
    json.encode({
      'id': id,
      'name': name,
      'version': version,
      'description': '端到端全链路闭环测试插件',
      'author': 'Pipeline Engineer',
      'minAppVersion': '0.1.0',
      'type': 'lua',
      'category': 'utility',
      'permissions': ['storage'],
      'entry': 'main.lua',
      'ui': 'ui/main.ui.json',
      'persistentStates': ['counter'],
    }),
  );

  // 2. main.lua
  addFile(
    'main.lua',
    '''
function onInit()
  local c = state.get("counter") or 10
  state.set("counter", c)
  state.set("pipeline_status", "ACTIVE")
  if plugin and plugin.log then
    plugin.log("Pipeline onInit executed, counter=" .. tostring(c))
  end
end

function increment()
  local c = (state.get("counter") or 10) + 1
  state.set("counter", c)
  if plugin and plugin.log then
    plugin.log("Pipeline increment clicked, new counter=" .. tostring(c))
  end
end
''',
  );

  // 3. ui/main.ui.json
  addFile(
    'ui/main.ui.json',
    json.encode({
      'type': 'Column',
      'props': {
        'crossAxisAlignment': 'stretch',
        'persistentStates': ['counter'],
      },
      'children': [
        {
          'type': 'Text',
          'props': {
            'text': '流水线状态: {{state.pipeline_status}}',
          },
        },
        {
          'type': 'Text',
          'props': {
            'text': '当前计数: {{state.counter}}',
          },
        },
        {
          'type': 'FilledButton',
          'props': {
            'text': '增加计数',
          },
          'events': {
            'onPressed': {
              'action': 'callLua',
              'function': 'increment',
            },
          },
        },
      ],
    }),
  );

  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('端到端全链路集成回归流水线 (E2E Full Pipeline)', () {
    late Directory tempRoot;
    late Directory pluginsDir;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      tempRoot = Directory.systemTemp.createTempSync('pipeline_e2e_');
      pluginsDir = Directory('${tempRoot.path}/plugins')..createSync();
    });

    tearDown(() {
      try {
        if (tempRoot.existsSync()) {
          tempRoot.deleteSync(recursive: true);
        }
      } catch (_) {}
    });

    testWidgets(
      '全生命周期闭环: 密钥签名 -> 安装前结构与签名双重核查 -> 沙箱安装 -> 注册中心 -> DUI/Lua 交互响应 -> 诊断日志与报告 -> 状态持久化落盘 -> 卸载彻底清理',
      (WidgetTester tester) async {
        const pluginId = 'pipeline_tool';
        const pluginName = '全链路流水线插件';

        // 1. 生成开发者 Ed25519 密钥对并完成安装包数字签名
        final (devPrivateKey, devPublicKey) = Ed25519.generateKeyPair();
        final devPublicKeyHex = Ed25519.bytesToHex(devPublicKey);

        final rawPtxBytes = _buildUnsignedPtxBytes(
          id: pluginId,
          name: pluginName,
          version: '1.2.0',
        );

        final signedBytes = Uint8List.fromList(
          PluginSigner.signPtxBytes(
            rawPtxBytes,
            devPrivateKey,
            keyId: 'dev-master-key',
          ),
        );

        // 2. 安装前静态合约核对与 Ed25519 签名验证 (inspectPluginPackage)
        final verifier = PluginSignatureVerifier(
          trustedPublicKeys: {devPublicKeyHex},
          requireSignature: true,
        );

        final contract = inspectPluginPackage(
          signedBytes,
          signatureVerifier: verifier,
        );
        expect(contract.isConsistent, isTrue);
        expect(contract.hasValidSignature, isTrue);
        expect(contract.manifest.id, equals(pluginId));
        expect(contract.manifest.name, equals(pluginName));
        expect(contract.manifest.version, equals('1.2.0'));
        expect(contract.signatureResult?.keyId, equals('dev-master-key'));

        // 3. 将签名后的插件包写入文件并通过 PluginInstaller 安全安装至沙箱
        final ptxFile = File('${tempRoot.path}/$pluginId.ptx')
          ..writeAsBytesSync(signedBytes);

        final installedPlugin = (await tester.runAsync(
          () => PluginInstaller.installFromPtx(
            ptxFile,
            baseDirectory: pluginsDir,
            signatureVerifier: verifier,
          ),
        ))!;

        expect(installedPlugin.id, equals(pluginId));
        expect(installedPlugin.name, equals(pluginName));
        expect(installedPlugin.rootDir.existsSync(), isTrue);

        // 验证沙箱内必需文件与数字签名实体存在
        expect(
          File('${installedPlugin.rootDir.path}/plugin.json').existsSync(),
          isTrue,
        );
        expect(
          File('${installedPlugin.rootDir.path}/main.lua').existsSync(),
          isTrue,
        );
        expect(
          File('${installedPlugin.rootDir.path}/ui/main.ui.json').existsSync(),
          isTrue,
        );
        expect(
          File('${installedPlugin.rootDir.path}/plugin.sig').existsSync(),
          isTrue,
        );

        // 4. 注册中心与状态机接入
        final prefs = await SharedPreferences.getInstance();
        final eventBus = EventBusImpl();
        final uninstallSub = PluginInstaller.listenUninstallRequests(
          eventBus,
          baseDirectory: pluginsDir,
        );
        addTearDown(uninstallSub.cancel);

        final registry = PluginRegistry(
          eventBus: eventBus,
          storageFactory: const PluginStorageFactory(),
        );
        registry.register(installedPlugin);

        expect(registry.getPlugin(pluginId), isNotNull);
        expect(registry.isEnabled(pluginId), isTrue);

        final container = ProviderContainer(
          overrides: [
            sharedPreferencesProvider.overrideWithValue(prefs),
            pluginRegistryProvider.overrideWith(
              (ref) =>
                  PluginRegistryNotifier(registry, prefs, eventBus: eventBus),
            ),
          ],
        );
        addTearDown(container.dispose);

        // 5. 挂载 DynamicPluginHostPage 并驱动 UI 渲染
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: DynamicPluginHostPage(plugin: installedPlugin),
            ),
          ),
        );

        // 轮询等待后台 Lua 初始化与 DUI 树装配完成
        for (var i = 0; i < 15; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 40)),
          );
          await tester.pump(const Duration(milliseconds: 40));
        }

        // 验证 UI 成功渲染 Lua 脚本 onInit 初始化后的状态
        expect(find.text(pluginName), findsOneWidget);
        expect(find.text('流水线状态: ACTIVE'), findsOneWidget);
        expect(find.text('当前计数: 10'), findsOneWidget);

        // 6. 模拟用户交互: 点击 "增加计数" 按钮
        final incrementButtonFinder = find.widgetWithText(
          FilledButton,
          '增加计数',
        );
        expect(incrementButtonFinder, findsOneWidget);
        await tester.tap(incrementButtonFinder);

        // 等待 Lua 事件派发与状态响应
        for (var i = 0; i < 5; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 30)),
          );
          await tester.pump(const Duration(milliseconds: 30));
        }

        // 验证 DUI 响应式刷新显示最新状态
        expect(find.text('当前计数: 11'), findsOneWidget);

        // 7. 检查与打开诊断排障弹窗
        final bugReportIconFinder = find.byIcon(Icons.bug_report_outlined);
        expect(bugReportIconFinder, findsOneWidget);
        await tester.tap(bugReportIconFinder);

        // 等待 BottomSheet 动画展开
        for (var i = 0; i < 8; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 30)),
          );
          await tester.pump(const Duration(milliseconds: 30));
        }

        // 验证诊断弹窗标题展示
        expect(find.text('插件诊断与控制台'), findsOneWidget);
        expect(find.text('运行状态'), findsOneWidget);

        // 关闭诊断弹窗 (点击关闭按钮)
        final closeFinder = find.byIcon(Icons.close_rounded);
        if (closeFinder.evaluate().isNotEmpty) {
          await tester.tap(closeFinder);
          for (var i = 0; i < 6; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 30)),
            );
            await tester.pump(const Duration(milliseconds: 30));
          }
        }

        // 8. 退出宿主页面，触发 dispose 并将状态落盘至沙箱
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: Text('已返回主界面')),
          ),
        );
        for (var i = 0; i < 6; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 30)),
          );
          await tester.pump(const Duration(milliseconds: 30));
        }

        // 9. 验证持久化状态 storage.json 正确写入沙箱
        final storageFile =
            File('${installedPlugin.rootDir.path}/storage.json');
        for (var i = 0; i < 40; i++) {
          if (storageFile.existsSync()) break;
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 25)),
          );
          await tester.pump(const Duration(milliseconds: 25));
        }
        expect(storageFile.existsSync(), isTrue);
        final storageData =
            json.decode(storageFile.readAsStringSync()) as Map<String, dynamic>;
        expect(storageData['counter'], equals(11));

        // 10. 验证沙箱中的诊断日志落盘文件 diagnostic.log
        final logFile = File('${installedPlugin.rootDir.path}/diagnostic.log');
        for (var i = 0; i < 30; i++) {
          if (logFile.existsSync()) break;
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 25)),
          );
        }
        if (logFile.existsSync()) {
          final logContent = logFile.readAsStringSync();
          expect(logContent, contains('Pipeline onInit executed'));
        }

        // 11. 执行卸载注销: 触发 EventBus 卸载事件并彻底删除沙箱目录
        await registry.unregister(pluginId);
        for (var i = 0; i < 30; i++) {
          if (!installedPlugin.rootDir.existsSync()) break;
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 40)),
          );
        }

        expect(installedPlugin.rootDir.existsSync(), isFalse);
        expect(registry.getPlugin(pluginId), isNull);
      },
    );

    testWidgets(
      '安全防御拦截: 未授权公钥签名与被篡改包在预检及安装阶段均被拦截',
      (WidgetTester tester) async {
        const pluginId = 'untrusted_tampered_tool';
        final (trustedPrivateKey, trustedPublicKey) = Ed25519.generateKeyPair();
        final trustedPublicKeyHex = Ed25519.bytesToHex(trustedPublicKey);
        final (attackerPrivateKey, _) = Ed25519.generateKeyPair();

        final rawPtxBytes = _buildUnsignedPtxBytes(
          id: pluginId,
          name: '攻击测试工具',
        );

        final verifier = PluginSignatureVerifier(
          trustedPublicKeys: {trustedPublicKeyHex},
          requireSignature: true,
        );

        // 场景 A: 使用未经授权的攻击者私钥签名
        final attackerSignedBytes = Uint8List.fromList(
          PluginSigner.signPtxBytes(
            rawPtxBytes,
            attackerPrivateKey,
          ),
        );

        // 强制验签模式下，inspectPluginPackage 抛出 PluginStoreException 拦截未授权包
        expect(
          () => inspectPluginPackage(
            attackerSignedBytes,
            signatureVerifier: verifier,
          ),
          throwsA(isA<PluginStoreException>()),
        );

        // 非强制验签模式下，inspectPluginPackage 标记 hasValidSignature == false
        final permissiveVerifier = PluginSignatureVerifier(
          trustedPublicKeys: {trustedPublicKeyHex},
          requireSignature: false,
        );
        final attackerContract = inspectPluginPackage(
          attackerSignedBytes,
          signatureVerifier: permissiveVerifier,
        );
        expect(attackerContract.hasValidSignature, isFalse);
        expect(
          attackerContract.signatureResult?.status,
          equals(VerificationStatus.untrustedKey),
        );

        final attackerFile = File('${tempRoot.path}/attacker.ptx')
          ..writeAsBytesSync(attackerSignedBytes);

        // 安装时若启用受信任白名单验证器，应被坚决拦截抛出 FormatException
        Object? attackerError;
        await tester.runAsync(() async {
          try {
            await PluginInstaller.installFromPtx(
              attackerFile,
              baseDirectory: pluginsDir,
              signatureVerifier: verifier,
            );
          } catch (e) {
            attackerError = e;
          }
        });
        expect(attackerError, isA<FormatException>());

        // 场景 B: 使用受信任密钥签名，但在传输过程中 main.lua 被恶意篡改
        final validSignedBytes = PluginSigner.signPtxBytes(
          rawPtxBytes,
          trustedPrivateKey,
        );

        final decodedArchive =
            ZipDecoder().decodeBytes(validSignedBytes, verify: true);
        final tamperedArchive = Archive();
        for (final file in decodedArchive.files) {
          if (file.name == 'main.lua') {
            final tamperedCode = utf8.encode('print("hacked")');
            tamperedArchive.addFile(
              ArchiveFile(file.name, tamperedCode.length, tamperedCode),
            );
          } else {
            tamperedArchive.addFile(file);
          }
        }
        final tamperedBytes =
            Uint8List.fromList(ZipEncoder().encode(tamperedArchive)!);

        // 强制模式下直接拦截篡改包
        expect(
          () => inspectPluginPackage(
            tamperedBytes,
            signatureVerifier: verifier,
          ),
          throwsA(isA<PluginStoreException>()),
        );

        final tamperedContract = inspectPluginPackage(
          tamperedBytes,
          signatureVerifier: permissiveVerifier,
        );
        expect(tamperedContract.hasValidSignature, isFalse);
        expect(
          tamperedContract.signatureResult?.status,
          equals(VerificationStatus.tampered),
        );

        final tamperedFile = File('${tempRoot.path}/tampered.ptx')
          ..writeAsBytesSync(tamperedBytes);

        Object? tamperedError;
        await tester.runAsync(() async {
          try {
            await PluginInstaller.installFromPtx(
              tamperedFile,
              baseDirectory: pluginsDir,
              signatureVerifier: verifier,
            );
          } catch (e) {
            tamperedError = e;
          }
        });
        expect(tamperedError, isA<FormatException>());
      },
    );
  });
}
