import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_toolbox/src/plugin_store/store_service.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';

/// 内存商店替身：目录与安装包全部预置，不触网。
class FakeStoreSource implements PluginStoreSource {
  FakeStoreSource({
    required this.entries,
    this.packages = const {},
    this.catalogError,
    this.downloadError,
  });

  final List<PluginStoreEntry> entries;
  final Map<String, Uint8List> packages;

  /// 非空时 fetchCatalog 抛出该异常
  final PluginStoreException? catalogError;

  /// 非空时 downloadPackage 抛出该异常
  final PluginStoreException? downloadError;

  int downloadCount = 0;

  @override
  Future<PluginStoreCatalog> fetchCatalog() async {
    final error = catalogError;
    if (error != null) throw error;
    return PluginStoreCatalog(
      entries: entries,
      revision: 'test-revision',
      fetchedAt: DateTime(2026, 1, 1),
    );
  }

  @override
  Future<Uint8List> downloadPackage(PluginStoreEntry entry) async {
    downloadCount++;
    final error = downloadError;
    if (error != null) throw error;
    final bytes = packages[entry.id];
    if (bytes == null) {
      throw PluginStoreException('远端缺少安装包 ${entry.id}.ptx');
    }
    return bytes;
  }
}

/// 构造一个内容合法、可被 PluginInstaller 真正解压安装的 .ptx
Uint8List buildPtx({
  required String id,
  String name = 'Fake Plugin',
  String version = '1.0.0',
  String entry = 'main.lua',
  String ui = 'ui/main.ui.json',
}) {
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
      'author': 'Tester',
      'type': 'lua',
      'category': 'encoding',
      'permissions': ['clipboard'],
      'entry': entry,
      'ui': ui,
    }),
  );
  add(entry, 'return nil');
  add(ui, '{"type":"Column","children":[]}');
  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}

PluginStoreEntry storeEntry({
  String id = 'store_tool',
  String version = '1.1.0',
  String? minAppVersion,
}) {
  return PluginStoreEntry(
    id: id,
    name: '商店插件',
    version: version,
    description: '来自 plugin-source 的简介',
    author: 'PluginToolbox Team',
    category: 'encoding',
    permissions: const ['clipboard'],
    minAppVersion: minAppVersion,
    packageName: '$id.ptx',
    packageSizeBytes: 2048,
    packageApiUrl: 'https://api.github.com/repos/x/y/contents/dist/$id.ptx?ref=abc',
    manifestApiUrl: 'https://api.github.com/repos/x/y/contents/plugin-source/$id/plugin.json',
    sourcePath: 'plugin-source/$id',
  );
}

ToolPlugin installedPlugin(String id, String version) => DynamicPlugin(
      manifest: PluginManifest(
        id: id,
        name: '本地 $id',
        version: version,
        description: '本地版本',
        author: 'Tester',
        type: 'lua',
        category: PluginCategory.encoding,
        permissions: const [],
        entry: 'main.lua',
        ui: 'ui/main.ui.json',
      ),
      rootDir: Directory('.'),
    );

PluginStoreCatalog catalogOf(List<PluginStoreEntry> entries) => PluginStoreCatalog(
      entries: entries,
      revision: 'test-revision',
      fetchedAt: DateTime(2026, 1, 1),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory pluginsRoot;
  late Directory tempRoot;

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return pluginsRoot.path;
        }
        return null;
      },
    );
    pluginsRoot = await Directory.systemTemp.createTemp('store_app_docs_');
    tempRoot = await Directory.systemTemp.createTemp('store_temp_');
  });

  tearDown(() async {
    for (final dir in [pluginsRoot, tempRoot]) {
      if (dir.existsSync()) await dir.delete(recursive: true);
    }
  });

  group('PluginStoreService.buildItems 安装态推导', () {
    test('未安装 / 可更新 / 已是最新 三种状态与本地版本号', () {
      final service = PluginStoreService(
        source: FakeStoreSource(entries: const []),
      );

      final items = service.buildItems(
        catalog: catalogOf([
          storeEntry(id: 'new_tool', version: '1.0.0'),
          storeEntry(id: 'old_tool', version: '2.0.0'),
          storeEntry(id: 'same_tool', version: '1.0.0'),
        ]),
        installedPlugins: [
          installedPlugin('old_tool', '1.0.0'),
          installedPlugin('same_tool', '1.0.0'),
        ],
        appVersion: '0.1.0',
      );

      expect(items.map((i) => i.id).toList(), ['new_tool', 'old_tool', 'same_tool']);
      expect(items[0].state, PluginStoreInstallState.notInstalled);
      expect(items[0].installedVersion, isNull);
      expect(items[1].state, PluginStoreInstallState.updateAvailable);
      expect(items[1].installedVersion, '1.0.0');
      expect(items[2].state, PluginStoreInstallState.upToDate);
      expect(items[2].installedVersion, '1.0.0');
    });

    test('minAppVersion 高于宿主版本时标记为不满足', () {
      final service = PluginStoreService(
        source: FakeStoreSource(entries: const []),
      );

      final items = service.buildItems(
        catalog: catalogOf([
          storeEntry(id: 'future_tool', minAppVersion: '9.9.9'),
          storeEntry(id: 'ok_tool', minAppVersion: '0.0.1'),
          storeEntry(id: 'any_tool'),
        ]),
        installedPlugins: const [],
        appVersion: '0.1.0',
      );

      expect(items[0].minAppVersionSatisfied, isFalse);
      expect(items[1].minAppVersionSatisfied, isTrue);
      expect(items[2].minAppVersionSatisfied, isTrue);
    });
  });

  group('PluginStoreService.install 下载与安装编排', () {
    test('下载后落盘安装, 并清理临时安装包', () async {
      final source = FakeStoreSource(
        entries: [storeEntry(id: 'store_tool')],
        packages: {
          'store_tool': buildPtx(id: 'store_tool', name: '商店插件', version: '1.1.0'),
        },
      );
      final service = PluginStoreService(
        source: source,
        temporaryDirectoryProvider: () async => tempRoot,
      );

      final outcome = await service.install(storeEntry(id: 'store_tool'));

      expect(source.downloadCount, 1);
      expect(outcome.plugin.id, 'store_tool');
      expect(outcome.plugin.version, '1.1.0');
      expect(outcome.versionMatched, isTrue);
      expect(outcome.warnings, isEmpty);

      // 安装包解压到沙箱目录, 临时 .ptx 已清理
      expect(File('${pluginsRoot.path}/plugins/store_tool/plugin.json').existsSync(), isTrue);
      expect(File('${tempRoot.path}/store_tool.ptx').existsSync(), isFalse);
    });

    test('安装包版本低于商店清单版本时给出非阻断提示', () async {
      final service = PluginStoreService(
        source: FakeStoreSource(
          entries: [storeEntry(id: 'stale_tool', version: '2.0.0')],
          packages: {
            'stale_tool': buildPtx(id: 'stale_tool', version: '1.0.0'),
          },
        ),
        temporaryDirectoryProvider: () async => tempRoot,
      );

      final outcome = await service.install(storeEntry(id: 'stale_tool', version: '2.0.0'));

      expect(outcome.versionMatched, isFalse);
      expect(outcome.warnings.single, contains('低于商店清单版本'));
      // 仍然完成安装: 提示不阻断流程
      expect(File('${pluginsRoot.path}/plugins/stale_tool/main.lua').existsSync(), isTrue);
    });

    test('下载失败时不落盘、不产生半成品插件目录', () async {
      final service = PluginStoreService(
        source: FakeStoreSource(
          entries: [storeEntry(id: 'broken_tool')],
          downloadError: const PluginStoreException('无法连接插件商店，请检查网络后重试'),
        ),
        temporaryDirectoryProvider: () async => tempRoot,
      );

      await expectLater(
        service.install(storeEntry(id: 'broken_tool')),
        throwsA(isA<PluginStoreException>()),
      );
      expect(Directory('${pluginsRoot.path}/plugins/broken_tool').existsSync(), isFalse);
      expect(File('${tempRoot.path}/broken_tool.ptx').existsSync(), isFalse);
    });

    test('同 ID 重复安装即更新, 沙箱目录被整体替换', () async {
      final service = PluginStoreService(
        source: FakeStoreSource(
          entries: [storeEntry(id: 'update_tool', version: '2.0.0')],
          packages: {
            'update_tool': buildPtx(id: 'update_tool', version: '2.0.0'),
          },
        ),
        temporaryDirectoryProvider: () async => tempRoot,
      );

      final first = await service.install(storeEntry(id: 'update_tool', version: '1.0.0'));
      expect(first.plugin.version, '2.0.0');

      final second = await service.install(storeEntry(id: 'update_tool', version: '2.0.0'));
      expect(second.plugin.version, '2.0.0');
      expect(File('${pluginsRoot.path}/plugins/update_tool/plugin.json').existsSync(), isTrue);
    });

    test('安装包缺少清单时抛出可展示错误并清理临时文件', () async {
      final archive = Archive();
      final junk = utf8.encode('return nil');
      archive.addFile(ArchiveFile('main.lua', junk.length, junk));

      final service = PluginStoreService(
        source: FakeStoreSource(
          entries: [storeEntry(id: 'no_manifest')],
          packages: {'no_manifest': Uint8List.fromList(ZipEncoder().encode(archive)!)},
        ),
        temporaryDirectoryProvider: () async => tempRoot,
      );

      await expectLater(
        service.install(storeEntry(id: 'no_manifest')),
        throwsA(isA<PluginStoreException>()
            .having((e) => e.message, 'message', contains('plugin.json'))),
      );
      // 契约核对发生在落盘之前, 目录中不应出现任何半成品
      expect(Directory('${pluginsRoot.path}/plugins/no_manifest').existsSync(), isFalse);
      expect(File('${tempRoot.path}/no_manifest.ptx').existsSync(), isFalse);
    });
  });
}

