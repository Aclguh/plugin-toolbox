import 'dart:io';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (methodCall) async {
        if (methodCall.method == 'getApplicationDocumentsDirectory') {
          return '.';
        }
        return null;
      },
    );
  });

  final Directory tempDirFactory = Directory.systemTemp;

  /// 构造一个 .ptx (ZIP) 压缩包
  Uint8List buildPtx(Map<String, List<int>> entries) {
    final archive = Archive();
    entries.forEach((name, content) {
      archive.addFile(ArchiveFile(name, content.length, content));
    });
    return Uint8List.fromList(ZipEncoder().encode(archive)!);
  }

  Uint8List utf8Bytes(String s) => Uint8List.fromList(s.codeUnits);

  Map<String, List<int>> validEntries({
    String id = 'installer_test',
    String entry = 'main.lua',
    String ui = 'ui/main.ui.json',
  }) {
    return {
      'plugin.json': utf8Bytes('{"id":"$id","name":"Installer Test",'
          '"version":"1.0.0","description":"d","author":"a","type":"lua",'
          '"category":"utility","entry":"$entry","ui":"$ui"}'),
      entry: utf8Bytes('return 1'),
      ui: utf8Bytes('{"type":"Column","children":[]}'),
    };
  }

  Future<File> writeTempPtx(Uint8List bytes) async {
    final dir = await tempDirFactory.createTemp('ptx_test_');
    final file = File('${dir.path}/test.ptx');
    await file.writeAsBytes(bytes);
    return file;
  }

  Future<void> cleanInstalledPluginsDir() async {
    final dir = Directory('./plugins');
    if (dir.existsSync()) {
      await dir.delete(recursive: true);
    }
  }

  tearDown(() async {
    await cleanInstalledPluginsDir();
  });

  group('PluginInstaller 安全防线', () {
    test('超大安装包被拒绝', () async {
      // 大小检查发生在 ZIP 解析之前, 因此非压缩包的超大文件同样会在此拦截
      final oversized = Uint8List(PluginInstaller.maxPackageSizeBytes + 1);
      final file = await writeTempPtx(oversized);

      await expectLater(
        PluginInstaller.installFromPtx(file),
        throwsFormatException,
      );
      await file.parent.delete(recursive: true);
    });

    test('缺少 plugin.json 清单的安装包被拒绝', () async {
      final file = await writeTempPtx(buildPtx({
        'main.lua': utf8Bytes('return 1'),
      }));

      await expectLater(
        PluginInstaller.installFromPtx(file),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('plugin.json'),
        )),
      );
      await file.parent.delete(recursive: true);
    });

    test('非法插件 ID 被拒绝', () async {
      final file = await writeTempPtx(buildPtx(validEntries(id: 'BAD-ID!')));

      await expectLater(
        PluginInstaller.installFromPtx(file),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('ID'),
        )),
      );
      await file.parent.delete(recursive: true);
    });

    test('缺少入口脚本或 UI 描述的安装包被拒绝', () async {
      final entries = validEntries();
      entries.remove('main.lua');
      final file = await writeTempPtx(buildPtx(entries));

      await expectLater(
        PluginInstaller.installFromPtx(file),
        throwsFormatException,
      );
      await file.parent.delete(recursive: true);
    });

    test('非 ZIP 格式的安装包被拒绝并抛出 FormatException', () async {
      final file = await writeTempPtx(Uint8List.fromList(
          List<int>.generate(1024, (i) => i % 256)));

      await expectLater(
        PluginInstaller.installFromPtx(file),
        throwsFormatException,
      );
      await file.parent.delete(recursive: true);
    });

    test('Zip Slip 路径穿越条目被拦截', () async {
      final maliciousCases = <String, List<int>>{
        ...validEntries(),
        '../evil.txt': utf8Bytes('evil'),
        'sub/../../evil.txt': utf8Bytes('evil'),
        r'C:\evil.bat': utf8Bytes('evil'),
        r'\\server\share\evil': utf8Bytes('evil'),
        '/abs/evil.txt': utf8Bytes('evil'),
      };
      final file = await writeTempPtx(buildPtx(maliciousCases));

      await expectLater(
        PluginInstaller.installFromPtx(file),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('非法的包内相对路径'),
        )),
      );
      await file.parent.delete(recursive: true);
      // 拦截发生时不得有任何文件逃逸出沙箱安装目录
      expect(File('./plugins/evil.txt').existsSync(), isFalse);
    });

    test('合法安装包解压成功且文件落位正确', () async {
      final file = await writeTempPtx(buildPtx({
        ...validEntries(),
        'icon.png': Uint8List.fromList(
            List<int>.generate(64, (i) => Random().nextInt(256))),
      }));

      final plugin = await PluginInstaller.installFromPtx(file);
      expect(plugin.id, 'installer_test');
      expect(plugin.rootDir.path, contains('plugins/installer_test'));

      final root = plugin.rootDir;
      expect(File('${root.path}/plugin.json').existsSync(), isTrue);
      expect(File('${root.path}/main.lua').existsSync(), isTrue);
      expect(File('${root.path}/ui/main.ui.json').existsSync(), isTrue,
          reason: '多级子目录应随解压自动创建');
      expect(File('${root.path}/icon.png').existsSync(), isTrue);
      expect(
        File('${root.path}/main.lua').readAsStringSync(),
        'return 1',
      );

      await file.parent.delete(recursive: true);
    });

    test('uninstall 清理沙箱目录', () async {
      final file = await writeTempPtx(buildPtx(validEntries()));
      final plugin = await PluginInstaller.installFromPtx(file);
      expect(plugin.rootDir.existsSync(), isTrue);

      await PluginInstaller.uninstall(plugin.id);
      expect(plugin.rootDir.existsSync(), isFalse);

      await file.parent.delete(recursive: true);
    });
  });

  group('PluginManifest 安全解析', () {
    test('缺少必填字段 id 抛出明确 FormatException', () {
      expect(
        () => PluginManifest.fromJson({
          'name': 'No Id',
          'type': 'lua',
        }),
        throwsA(isA<FormatException>().having(
          (e) => e.message, 'message', contains('id'))),
      );
    });

    test('缺少必填字段 name 抛出明确 FormatException', () {
      expect(
        () => PluginManifest.fromJson({'id': 'some_plugin'}),
        throwsA(isA<FormatException>().having(
            (e) => e.message, 'message', contains('name'))),
      );
    });

    test('字段类型错误时安全降级而非 TypeError 崩溃', () {
      final manifest = PluginManifest.fromJson({
        'id': 12345, // 数字而非字符串
        'name': ['A', 'B'], // 列表而非字符串
        'version': 42,
        'permissions': 'not-a-list',
        'settings': 'not-a-list',
      });
      expect(manifest.id, '12345');
      expect(manifest.name, '[A, B]');
      expect(manifest.version, '42');
    });

    test('清单根不是 JSON 对象时抛出 FormatException', () {
      expect(
        () => PluginManifest.fromJsonString('[1,2,3]'),
        throwsFormatException,
      );
    });

    test('storageQuotaMb 安全解析与缺省默认值', () {
      final defaultManifest = PluginManifest.fromJson({
        'id': 'quota_default',
        'name': 'Quota Default',
      });
      expect(defaultManifest.storageQuotaMb, 50);

      final customManifest = PluginManifest.fromJson({
        'id': 'quota_custom',
        'name': 'Quota Custom',
        'storageQuotaMb': 100,
      });
      expect(customManifest.storageQuotaMb, 100);
      expect(customManifest.toJson()['storageQuotaMb'], 100);
    });
  });

  group('沙箱路径校验与存储配额生产实现', () {
    test('isSafeRelativeEntry 拦截全部穿越向量', () {
      expect(SandboxPath.isSafeRelativeEntry('ui/main.ui.json'), isTrue);
      expect(SandboxPath.isSafeRelativeEntry('..\\evil'), isFalse);
      expect(SandboxPath.isSafeRelativeEntry('....//escape'), isFalse);
      expect(SandboxPath.isSafeRelativeEntry(r'Z:\evil'), isFalse);
      expect(SandboxPath.isSafeRelativeEntry('a/\u0000b'), isFalse);
    });

    test('isSafeSubpath 允许沙箱内路径', () {
      expect(SandboxPath.isSafeSubpath('/data/plugins/x', 'a/b.txt'), isTrue);
    });

    test('PluginContext.checkStorageQuota 配额容量计算与拦截', () async {
      final tempDir = await Directory.systemTemp.createTemp('ptx_quota_test');
      final ctx = PluginContext(
        pluginId: 'quota_test',
        storage: PluginStorageImpl(namespace: 'quota_test'),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {},
        rootDir: tempDir,
        storageQuotaMb: 1, // 1MB 配额
      );

      // 目录为空时，额外写入 500KB 合法
      expect(ctx.checkStorageQuota(500 * 1024), isTrue);

      // 写入 800KB 文件
      final file = File('${tempDir.path}/test.bin');
      await file.writeAsBytes(List<int>.filled(800 * 1024, 0));
      ctx.invalidateStorageQuotaCache();

      // 当前已有 800KB，尝试再写入 300KB 超出 1MB 配额 (800 + 300 = 1100 > 1024)
      expect(ctx.checkStorageQuota(300 * 1024), isFalse);

      // 尝试再写入 100KB 在配额内 (800 + 100 = 900 <= 1024)
      expect(ctx.checkStorageQuota(100 * 1024), isTrue);

      // 验证内存增量维护
      ctx.updateUsedBytes(200 * 1024);
      // 当前内存缓存为 800 + 200 = 1000KB，尝试再写入 100KB 超出 1MB 配额 (1000 + 100 = 1100 > 1024)
      expect(ctx.checkStorageQuota(100 * 1024), isFalse);

      await tempDir.delete(recursive: true);
    });
  });
}
