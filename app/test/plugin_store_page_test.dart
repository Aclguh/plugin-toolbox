import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_toolbox/src/plugin_store/plugin_store_page.dart';
import 'package:plugin_toolbox/src/plugin_store/store_providers.dart';
import 'package:plugin_toolbox/src/plugin_store/store_service.dart';
import 'package:plugin_toolbox/src/providers/app_providers.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 内存商店替身：目录与安装包全部预置，测试期间绝不触网。
class FakeStoreSource implements PluginStoreSource {
  FakeStoreSource({
    required this.entries,
    this.packages = const {},
    this.error,
  });

  final List<PluginStoreEntry> entries;
  final Map<String, Uint8List> packages;
  final PluginStoreException? error;

  int downloadCount = 0;

  @override
  Future<PluginStoreCatalog> fetchCatalog() async {
    final failure = error;
    if (failure != null) throw failure;
    return PluginStoreCatalog(
      entries: entries,
      revision: 'test-revision',
      fetchedAt: DateTime(2026, 1, 1),
    );
  }

  @override
  Future<Uint8List> downloadPackage(PluginStoreEntry entry) async {
    downloadCount++;
    final bytes = packages[entry.id];
    if (bytes == null) throw PluginStoreException('远端缺少安装包 ${entry.id}.ptx');
    return bytes;
  }
}

Uint8List buildPtx({required String id, required String name, required String version}) {
  final archive = Archive();
  void add(String path, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(path, bytes.length, bytes));
  }

  add(
    'plugin.json',
    json.encode({
      'id': id,
      'name': name,
      'version': version,
      'description': '来自商店的插件',
      'author': 'PluginToolbox Team',
      'type': 'lua',
      'category': 'encoding',
      'permissions': ['clipboard'],
      'entry': 'main.lua',
      'ui': 'ui/main.ui.json',
    }),
  );
  add('main.lua', 'return nil');
  add('ui/main.ui.json', '{"type":"Column","children":[]}');
  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}

PluginStoreEntry storeEntry({
  required String id,
  required String name,
  String version = '1.1.0',
  String description = 'Base64 文本编码与解码转换工具',
}) {
  return PluginStoreEntry(
    id: id,
    name: name,
    version: version,
    description: description,
    author: 'PluginToolbox Team',
    category: 'encoding',
    permissions: const ['clipboard', 'storage'],
    packageName: '$id.ptx',
    packageSizeBytes: 2048,
    packageApiUrl: 'https://api.github.com/x/$id.ptx?ref=abc',
    manifestApiUrl: 'https://api.github.com/x/$id/plugin.json',
    sourcePath: 'plugin-source/$id',
  );
}

ToolPlugin installedPlugin(String id, String name, String version) => DynamicPlugin(
      manifest: PluginManifest(
        id: id,
        name: name,
        version: version,
        description: '本地已安装版本',
        author: 'Tester',
        type: 'lua',
        category: PluginCategory.encoding,
        permissions: const [],
        entry: 'main.lua',
        ui: 'ui/main.ui.json',
      ),
      rootDir: Directory('.'),
    );

/// 读取真实下载落盘的 .ptx，按包内 plugin.json 解出清单并返回插件实例。
///
/// 只替代"解压落盘"这一步：包内清单的解析仍走生产模型，
/// 因此对任意测试条目都成立。全部使用同步文件 API——
/// fake-async 测试环境中异步文件 IO 的后续微任务不会被执行。
Future<DynamicPlugin> fakeInstaller(File file, Directory rootDir) async {
  expect(file.existsSync(), isTrue, reason: '安装前安装包必须已落盘');
  final bytes = file.readAsBytesSync();
  expect(bytes, isNotEmpty);

  final archive = ZipDecoder().decodeBytes(bytes);
  final manifestEntry = archive.findFile('plugin.json');
  expect(manifestEntry, isNotNull, reason: '安装包必须包含 plugin.json');
  final manifest = PluginManifest.fromJsonString(
    utf8.decode(manifestEntry!.content as List<int>),
  );

  return DynamicPlugin(manifest: manifest, rootDir: rootDir);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory appDocs;
  late Directory tempDir;

  Future<ProviderContainer> createStoreContainer(
    FakeStoreSource source, {
    bool fakeInstallerReturnsPlugin = false,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      pluginStoreServiceProvider.overrideWithValue(
        PluginStoreService(
          source: source,
          temporaryDirectoryProvider: () async => tempDir,
          // 测试聚焦商店页的编排（下载→安装→注册→刷新），
          // 解压落盘由 packages/core 与 store_service_test 覆盖，
          // 这里用替身安装器避免依赖 path_provider 原生通道
          installer: fakeInstallerReturnsPlugin
              ? (file) => fakeInstaller(file, tempDir)
              : null,
        ),
      ),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  Future<void> pumpStore(WidgetTester tester, ProviderContainer container) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: PluginStorePage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return appDocs.path;
        }
        return null;
      },
    );
    appDocs = await Directory.systemTemp.createTemp('store_page_docs_');
    tempDir = await Directory.systemTemp.createTemp('store_page_temp_');
  });

  tearDown(() async {
    for (final dir in [appDocs, tempDir]) {
      if (dir.existsSync()) await dir.delete(recursive: true);
    }
  });

  testWidgets('商店页展示线上条目的版本与简介, 并区分安装态', (WidgetTester tester) async {
    final source = FakeStoreSource(entries: [
      storeEntry(id: 'qr_tool', name: '二维码生成', version: '1.1.0', description: '文本与链接生成二维码'),
      storeEntry(id: 'hash_tool', name: '哈希计算器', version: '1.1.0', description: 'MD5 / SHA 摘要'),
    ]);
    final container = await createStoreContainer(source);
    container
        .read(pluginRegistryProvider)
        .register(installedPlugin('hash_tool', '哈希计算器', '1.1.0'));

    await pumpStore(tester, container);

    expect(find.text('插件商店'), findsOneWidget);
    expect(find.text('共 2 个插件'), findsOneWidget);

    // 版本与描述来自 plugin-source 清单
    expect(find.text('二维码生成'), findsOneWidget);
    expect(find.text('版本 1.1.0 · 编解码'), findsWidgets);
    expect(find.text('文本与链接生成二维码'), findsOneWidget);
    expect(find.text('MD5 / SHA 摘要'), findsOneWidget);

    // 未安装 -> 安装按钮; 已安装同版本 -> 已是最新
    expect(find.text('安装'), findsOneWidget);
    expect(find.text('已是最新'), findsOneWidget);
    expect(find.text('更新'), findsNothing);

    // 权限与体积等决策信息一并展示
    expect(find.textContaining('剪贴板/本地存储'), findsWidgets);
    expect(find.textContaining('2.0 KB'), findsWidgets);
  });

  testWidgets('本地版本落后时展示更新入口', (WidgetTester tester) async {
    final source = FakeStoreSource(entries: [
      storeEntry(id: 'qr_tool', name: '二维码生成', version: '1.1.0'),
    ]);
    final container = await createStoreContainer(source);
    container
        .read(pluginRegistryProvider)
        .register(installedPlugin('qr_tool', '二维码生成', '1.0.0'));

    await pumpStore(tester, container);

    expect(find.text('更新'), findsOneWidget);
    expect(find.text('本地已安装 1.0.0'), findsOneWidget);
  });

  testWidgets('点击安装先弹确认, 取消则不发起下载', (WidgetTester tester) async {
    final source = FakeStoreSource(
      entries: [storeEntry(id: 'qr_tool', name: '二维码生成')],
      packages: {'qr_tool': buildPtx(id: 'qr_tool', name: '二维码生成', version: '1.1.0')},
    );
    final container = await createStoreContainer(source);

    await pumpStore(tester, container);
    await tester.tap(find.text('安装'));
    await tester.pumpAndSettle();

    // 确认对话框展示安装决策信息
    expect(find.text('安装插件'), findsOneWidget);
    expect(find.text('二维码生成 v1.1.0'), findsOneWidget);
    expect(find.text('分类: 编解码'), findsOneWidget);
    expect(find.text('作者: PluginToolbox Team'), findsOneWidget);
    expect(find.text('体积: 2.0 KB'), findsOneWidget);
    expect(find.text('权限: 剪贴板、本地存储'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(source.downloadCount, 0);
    expect(container.read(pluginRegistryProvider).getPlugin('qr_tool'), isNull);
  });

  testWidgets('确认后完成下载安装并注册进插件列表', (WidgetTester tester) async {
    final source = FakeStoreSource(
      entries: [storeEntry(id: 'qr_tool', name: '二维码生成')],
      packages: {'qr_tool': buildPtx(id: 'qr_tool', name: '二维码生成', version: '1.1.0')},
    );
    final container = await createStoreContainer(source, fakeInstallerReturnsPlugin: true);

    await pumpStore(tester, container);
    await tester.tap(find.text('安装'));
    await tester.pumpAndSettle();

    // 点击确认: Dialog pop 与 _install 在同一次 pump 中推进
    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(FilledButton, '安装'),
    ));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 5));

    expect(source.downloadCount, 1);
    final registered = container.read(pluginRegistryProvider).getPlugin('qr_tool');
    expect(registered, isNotNull);
    expect(registered!.version, '1.1.0');
    expect(find.textContaining('二维码生成 v1.1.0 已安装'), findsOneWidget);
    // 安装完成后临时安装包不残留
    expect(File('${tempDir.path}/qr_tool.ptx').existsSync(), isFalse);
  });

  testWidgets('安装失败时给出可读提示且不注册半成品插件', (WidgetTester tester) async {
    final source = FakeStoreSource(
      entries: [storeEntry(id: 'qr_tool', name: '二维码生成')],
      // 未提供安装包 -> downloadPackage 抛 PluginStoreException
    );
    final container = await createStoreContainer(source);

    await pumpStore(tester, container);
    await tester.tap(find.text('安装'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(FilledButton, '安装'),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('远端缺少安装包'), findsOneWidget);
    expect(container.read(pluginRegistryProvider).getPlugin('qr_tool'), isNull);
  });

  testWidgets('目录加载失败时展示可重试的错误态', (WidgetTester tester) async {
    final source = FakeStoreSource(
      entries: const [],
      error: const PluginStoreException('无法连接插件商店，请检查网络后重试'),
    );
    final container = await createStoreContainer(source);

    await pumpStore(tester, container);

    expect(find.text('无法连接插件商店，请检查网络后重试'), findsOneWidget);
    expect(find.text('重新加载'), findsOneWidget);
  });

  testWidgets('空目录展示提示与重载入口', (WidgetTester tester) async {
    final source = FakeStoreSource(entries: const []);
    final container = await createStoreContainer(source);

    await pumpStore(tester, container);

    expect(find.text('远端插件目录为空'), findsOneWidget);
    expect(find.text('重新加载'), findsOneWidget);
  });
}

