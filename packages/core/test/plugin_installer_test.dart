import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    PluginInstaller.defaultPathProvider = DirectoryPathProvider(
      pluginsDirectory: Directory('./plugins'),
    );
    PluginLoader.defaultPathProvider = PluginInstaller.defaultPathProvider;
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
      final file = await writeTempPtx(
          Uint8List.fromList(List<int>.generate(1024, (i) => i % 256)));

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

    test('Zip Bomb 异常高膨胀比安装包被拦截', () async {
      // 6MB 全零数据经过 ZIP 压缩后仅数 KB，膨胀比远超 20 倍且总解压大小 > 5MB
      final hugeData = Uint8List(6 * 1024 * 1024);
      final file = await writeTempPtx(buildPtx({
        ...validEntries(),
        'bomb.dat': hugeData,
      }));

      await expectLater(
        PluginInstaller.installFromPtx(file),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('解压膨胀比超过安全限制'),
        )),
      );
      await file.parent.delete(recursive: true);
      expect(Directory('./plugins/installer_test').existsSync(), isFalse);
      // 流式解压中止后暂存目录必须一并清理，不得残留
      expect(
          Directory('./plugins/.installer_test.staging').existsSync(), isFalse);
    });

    test('声明解压体积超限的条目在解压前即被拦截', () async {
      // 单条目声明解压 51MB > 50MB 上限，凭 ZIP 中央目录前置拦截，
      // 全零内容压缩后仅数十 KB，无需真实解压即可判定
      final file = await writeTempPtx(buildPtx({
        ...validEntries(),
        'oversized.dat': Uint8List(51 * 1024 * 1024),
      }));

      await expectLater(
        PluginInstaller.installFromPtx(file),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('解压展开体积超限'),
        )),
      );
      await file.parent.delete(recursive: true);
      expect(Directory('./plugins/installer_test').existsSync(), isFalse);
      expect(
          Directory('./plugins/.installer_test.staging').existsSync(), isFalse);
    });

    test('条目数超限的安装包在解压前被拦截', () async {
      final entries = validEntries();
      for (var i = 0; i < PluginInstaller.maxEntryCount; i++) {
        entries['filler/$i.txt'] = utf8Bytes('$i');
      }
      final file = await writeTempPtx(buildPtx(entries));

      await expectLater(
        PluginInstaller.installFromPtx(file),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('条目数超限'),
        )),
      );
      await file.parent.delete(recursive: true);
      expect(Directory('./plugins/installer_test').existsSync(), isFalse);
    });

    test('升级安装解压失败时旧版本插件完整保留', () async {
      // 先安装 v1.0.0 正常版本
      final v1 = await writeTempPtx(buildPtx({
        ...validEntries(),
        'version.txt': utf8Bytes('v1'),
      }));
      final installed = await PluginInstaller.installFromPtx(v1);
      expect(File('${installed.rootDir.path}/version.txt').readAsStringSync(),
          'v1');
      await v1.parent.delete(recursive: true);

      // 再尝试用同 ID 的炸弹包升级，必须失败且旧版本不受任何影响
      final bomb = await writeTempPtx(buildPtx({
        ...validEntries(),
        'bomb.dat': Uint8List(6 * 1024 * 1024),
      }));
      await expectLater(
        PluginInstaller.installFromPtx(bomb),
        throwsFormatException,
      );
      await bomb.parent.delete(recursive: true);

      expect(
          File('${installed.rootDir.path}/plugin.json').existsSync(), isTrue);
      expect(File('${installed.rootDir.path}/version.txt').readAsStringSync(),
          'v1',
          reason: '升级失败不得丢失已安装的旧版本插件');
      // 暂存目录必须清理，备份目录在替换未发生时本就不应存在
      expect(
          Directory('./plugins/.installer_test.staging').existsSync(), isFalse);
      expect(
          Directory('./plugins/.installer_test.backup').existsSync(), isFalse);
    });

    test('升级安装成功时原子替换且旧版独有文件被移除', () async {
      // v1 带一个旧版独有的遗留文件
      final v1 = await writeTempPtx(buildPtx({
        ...validEntries(),
        'legacy.dat': utf8Bytes('legacy'),
      }));
      final installed = await PluginInstaller.installFromPtx(v1);
      expect(File('${installed.rootDir.path}/legacy.dat').existsSync(), isTrue);
      await v1.parent.delete(recursive: true);

      // v2 不含 legacy.dat，新增 new.dat
      final v2 = await writeTempPtx(buildPtx({
        ...validEntries(),
        'new.dat': utf8Bytes('new'),
      }));
      final upgraded = await PluginInstaller.installFromPtx(v2);
      await v2.parent.delete(recursive: true);

      expect(upgraded.rootDir.path, installed.rootDir.path);
      expect(File('${upgraded.rootDir.path}/new.dat').existsSync(), isTrue);
      expect(File('${upgraded.rootDir.path}/legacy.dat').existsSync(), isFalse,
          reason: '原子替换应整体换目录，旧版独有文件不得残留');
      // 成功后暂存与备份目录都必须清理
      expect(
          Directory('./plugins/.installer_test.staging').existsSync(), isFalse);
      expect(
          Directory('./plugins/.installer_test.backup').existsSync(), isFalse);
    });

    test('上次安装崩溃残留的暂存目录会被清理并正常安装', () async {
      // 模拟崩溃残留：暂存目录里丢一份垃圾文件
      final staleStaging = Directory('./plugins/.installer_test.staging');
      await staleStaging.create(recursive: true);
      await File('${staleStaging.path}/stale.junk').writeAsString('stale');

      final file = await writeTempPtx(buildPtx(validEntries()));
      final plugin = await PluginInstaller.installFromPtx(file);
      await file.parent.delete(recursive: true);

      expect(plugin.id, 'installer_test');
      expect(File('${plugin.rootDir.path}/plugin.json').existsSync(), isTrue);
      expect(File('${plugin.rootDir.path}/stale.junk').existsSync(), isFalse,
          reason: '残留的暂存垃圾不得混入正式安装目录');
      expect(staleStaging.existsSync(), isFalse);
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

    test('uninstall 清理沙箱目录与持久化存储数据', () async {
      SharedPreferences.setMockInitialValues({});
      final file = await writeTempPtx(buildPtx(validEntries()));
      final plugin = await PluginInstaller.installFromPtx(file);
      expect(plugin.rootDir.existsSync(), isTrue);

      const storageFactory = PluginStorageFactory();
      final storage = storageFactory.create(plugin.id);
      await storage.setString('test_pref', 'saved_data');
      expect(await storage.getString('test_pref'), 'saved_data');

      await PluginInstaller.uninstall(plugin.id);
      expect(plugin.rootDir.existsSync(), isFalse);
      expect(await storage.getString('test_pref'), isNull);

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
        throwsA(isA<FormatException>()
            .having((e) => e.message, 'message', contains('id'))),
      );
    });

    test('缺少必填字段 name 抛出明确 FormatException', () {
      expect(
        () => PluginManifest.fromJson({'id': 'some_plugin'}),
        throwsA(isA<FormatException>()
            .having((e) => e.message, 'message', contains('name'))),
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
      expect(
          SandboxPath.isSafeResolvedPath(
              '/data/plugins/x', '/data/plugins/x/a/b.txt'),
          isTrue);
      expect(
          SandboxPath.isSafeResolvedPath('/data/plugins/x', '/data/plugins/x'),
          isTrue);
      expect(SandboxPath.isSafeResolvedPath('/data/plugins/x', '/etc/passwd'),
          isFalse);
      expect(
          SandboxPath.isSafeResolvedPath(
              '/data/plugins/x', '/data/plugins/other'),
          isFalse);
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

      // 验证并发写入配额预扣除与回滚（防范 TOCTOU 竞态）
      ctx.invalidateStorageQuotaCache();
      expect(ctx.currentUsedBytes, 800 * 1024);
      // 预扣除 150KB (800 + 150 = 950 <= 1024) 成功
      expect(ctx.reserveStorageQuota(150 * 1024), isTrue);
      expect(ctx.reservedBytes, 150 * 1024);
      // 预扣后，再检查 100KB 应当被拦截 (800 + 150 + 100 = 1050 > 1024)
      expect(ctx.checkStorageQuota(100 * 1024), isFalse);
      // 回滚 150KB 后恢复放行
      ctx.rollbackStorageQuota(150 * 1024);
      expect(ctx.reservedBytes, 0);
      expect(ctx.checkStorageQuota(100 * 1024), isTrue);
      // 预扣并提交实际落盘
      expect(ctx.reserveStorageQuota(100 * 1024), isTrue);
      ctx.commitStorageQuota(100 * 1024, actualDelta: 100 * 1024);
      expect(ctx.reservedBytes, 0);
      expect(ctx.currentUsedBytes, 900 * 1024);

      await tempDir.delete(recursive: true);
    });

    test('PluginInstaller 校验 SHA-256 完整性哈希：合法放行，篡改或不匹配时拦截', () async {
      final customBaseDir = await tempDirFactory.createTemp('custom_sha_');
      final ptxBytes = buildPtx(validEntries(id: 'sha_test'));
      final ptxFile = await writeTempPtx(ptxBytes);

      final realSha256 = calculatePackageSha256(ptxBytes);
      expect(verifyPackageSha256(ptxBytes, realSha256), isTrue);

      // 1. 错误哈希拦截
      expect(
        () => PluginInstaller.installFromPtx(
          ptxFile,
          baseDirectory: customBaseDir,
          expectedSha256: 'deadbeef' * 8,
        ),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('SHA-256 完整性哈希校验失败'),
        )),
      );

      // 2. 正确十六进制哈希放行
      final p1 = await PluginInstaller.installFromPtx(
        ptxFile,
        baseDirectory: customBaseDir,
        expectedSha256: realSha256,
      );
      expect(p1.id, 'sha_test');

      // 3. 正确 base64 形式哈希放行
      final base64Sha = base64.encode(sha256.convert(ptxBytes).bytes);
      expect(verifyPackageSha256(ptxBytes, base64Sha), isTrue);
      final p2 = await PluginInstaller.installFromPtx(
        ptxFile,
        baseDirectory: customBaseDir,
        expectedSha256: base64Sha,
      );
      expect(p2.id, 'sha_test');

      await PluginInstaller.uninstall('sha_test', baseDirectory: customBaseDir);
      await customBaseDir.delete(recursive: true);
    });

    test('PluginInstaller 支持注入 baseDirectory 独立安装与卸载', () async {
      final customBaseDir = await tempDirFactory.createTemp('custom_plugins_');
      final ptxFile =
          await writeTempPtx(buildPtx(validEntries(id: 'injected_test')));

      final plugin = await PluginInstaller.installFromPtx(
        ptxFile,
        baseDirectory: customBaseDir,
      );

      expect(plugin.id, 'injected_test');
      expect(plugin.rootDir.path.startsWith(customBaseDir.path), isTrue);
      expect(await File('${plugin.rootDir.path}/plugin.json').exists(), isTrue);

      // 验证 uninstall 支持注入 baseDirectory
      await PluginInstaller.uninstall('injected_test',
          baseDirectory: customBaseDir);
      expect(await plugin.rootDir.exists(), isFalse);

      await customBaseDir.delete(recursive: true);
    });

    test('PluginContext.scanUsedBytes 异步扫描刷新缓存且与配额判定一致', () async {
      final tempDir = await Directory.systemTemp.createTemp('ptx_scan_test');
      // 写入两级目录共 100KB 文件
      await Directory('${tempDir.path}/sub').create(recursive: true);
      await File('${tempDir.path}/a.bin')
          .writeAsBytes(List<int>.filled(60 * 1024, 1));
      await File('${tempDir.path}/sub/b.bin')
          .writeAsBytes(List<int>.filled(40 * 1024, 2));

      final ctx = PluginContext(
        pluginId: 'scan_test',
        storage: PluginStorageImpl(namespace: 'scan_test'),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {},
        rootDir: tempDir,
        storageQuotaMb: 1, // 1MB 配额
      );

      // 异步扫描返回精确字节数并刷新缓存（当前缓存为空）
      final scanned = await ctx.scanUsedBytes();
      expect(scanned, 100 * 1024);
      expect(ctx.currentUsedBytes, 100 * 1024,
          reason: '扫描后同步读路径必须命中缓存，不再触发磁盘 IO');

      // 配额判定与扫描结果一致：再写 1MB 超限，再写 900KB 在配额内
      expect(ctx.checkStorageQuota(1024 * 1024), isFalse);
      expect(ctx.checkStorageQuota(900 * 1024), isTrue);

      // 文件变动后重新异步扫描，缓存同步更新
      await File('${tempDir.path}/a.bin').delete();
      final rescanned = await ctx.scanUsedBytes();
      expect(rescanned, 40 * 1024);
      expect(ctx.currentUsedBytes, 40 * 1024);

      // rootDir 为 null 时扫描返回 0 且配额恒放行
      final noDirCtx = PluginContext(
        pluginId: 'scan_none',
        storage: PluginStorageImpl(namespace: 'scan_none'),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {},
      );
      expect(await noDirCtx.scanUsedBytes(), 0);
      expect(noDirCtx.checkStorageQuota(1024 * 1024 * 1024), isTrue);

      await tempDir.delete(recursive: true);
    });

    test('入口脚本为预编译 Lua 字节码时拒绝安装并抛出 FormatException', () async {
      final bytecodeEntries = validEntries(id: 'bytecode_attack');
      // 构造 \x1bLua 预编译字节码头
      bytecodeEntries['main.lua'] = [0x1B, 0x4C, 0x75, 0x61, 0x51, 0x00, 0x01];
      final ptx = await writeTempPtx(buildPtx(bytecodeEntries));

      expect(
        () => PluginInstaller.installFromPtx(ptx),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('安全策略拦截: 插件入口脚本禁止使用预编译 Lua 字节码'),
        )),
      );

      expect(PluginInstaller.isLuaBytecode([0x1B, 0x4C, 0x75, 0x61]), isTrue);
      expect(PluginInstaller.isLuaBytecode([0x1B, 0x4C, 0x75]), isFalse);
      expect(PluginInstaller.isLuaBytecode(utf8Bytes('print("ok")')), isFalse);
    });

    test('导出插件为 .ptx 归档包并自动排除运行时数据与隐藏文件', () async {
      final baseDir = await Directory.systemTemp.createTemp('ptx_export_test_');
      final pluginDir = Directory('${baseDir.path}/demo_tool');
      await pluginDir.create(recursive: true);

      // 写入标准插件必要文件
      await File('${pluginDir.path}/plugin.json').writeAsString(jsonEncode({
        'id': 'demo_tool',
        'name': 'Demo Tool',
        'version': '1.0.0',
        'description': 'Export Demo',
        'author': 'Tester',
        'minAppVersion': '0.2.1',
        'type': 'lua',
        'category': 'utility',
        'permissions': ['clipboard'],
        'entry': 'main.lua',
        'ui': 'ui/main.ui.json',
      }));
      await File('${pluginDir.path}/main.lua').writeAsString('print("hello")');
      final uiDir = Directory('${pluginDir.path}/ui');
      await uiDir.create(recursive: true);
      await File('${uiDir.path}/main.ui.json').writeAsString(jsonEncode({
        'type': 'Text',
        'props': {'text': 'hi'}
      }));

      // 写入运行期沙箱数据与隐藏文件（导出时应被自动过滤）
      await File('${pluginDir.path}/storage.json')
          .writeAsString('{"key": "secret"}');
      await File('${pluginDir.path}/storage.json.bak')
          .writeAsString('{"key": "backup"}');
      await File('${pluginDir.path}/.hidden_config').writeAsString('sensitive');
      await File('${uiDir.path}/.DS_Store').writeAsString('junk');

      // 1. 测试 exportToBytes
      final bytes = await PluginInstaller.exportToBytes(pluginDir);
      expect(bytes, isNotEmpty);

      // 2. 测试 exportToPtx
      final outPtx = File('${baseDir.path}/exported_demo.ptx');
      final resultFile = await PluginInstaller.exportToPtx(pluginDir, outPtx);
      expect(resultFile.path, outPtx.path);
      expect(await resultFile.exists(), isTrue);

      // 3. 解包校验内容与过滤项
      final archive = ZipDecoder().decodeBytes(await resultFile.readAsBytes());
      final filenames = archive.files.map((f) => f.name).toSet();

      expect(filenames.contains('plugin.json'), isTrue);
      expect(filenames.contains('main.lua'), isTrue);
      expect(filenames.contains('ui/main.ui.json'), isTrue);

      // 验证持久化与临时隐藏文件被彻底排除
      expect(filenames.contains('storage.json'), isFalse);
      expect(filenames.contains('storage.json.bak'), isFalse);
      expect(filenames.contains('.hidden_config'), isFalse);
      expect(filenames.contains('ui/.DS_Store'), isFalse);

      // 4. 验证导出的包可以直接被重新成功安装
      final installed = await PluginInstaller.installFromPtx(
        resultFile,
        baseDirectory: Directory('${baseDir.path}/install_target'),
      );
      expect(installed.id, 'demo_tool');
      expect(installed.name, 'Demo Tool');

      await baseDir.delete(recursive: true);
    });

    test('覆盖更新已存在插件时，原沙箱中的持久化 storage.json 与用户数据文件无损保留', () async {
      final baseDir = await tempDirFactory.createTemp('ptx_upgrade_test_');

      // 1. 安装 1.0.0 版本
      final v1PtxBytes = buildPtx({
        'plugin.json': utf8Bytes('{"id":"upgrade_demo","name":"Upgrade Demo",'
            '"version":"1.0.0","description":"v1","author":"a","type":"lua",'
            '"category":"utility","entry":"main.lua","ui":"ui/main.ui.json"}'),
        'main.lua': utf8Bytes('print("v1")'),
        'ui/main.ui.json': utf8Bytes('{"type":"Column","children":[]}'),
      });
      final v1File = await writeTempPtx(v1PtxBytes);
      final pluginV1 = await PluginInstaller.installFromPtx(
        v1File,
        baseDirectory: baseDir,
      );
      expect(pluginV1.manifest.version, '1.0.0');

      // 2. 模拟运行期用户产生了持久化状态与业务文件
      final sandboxDir = pluginV1.rootDir!;
      final storageFile = File('${sandboxDir.path}/storage.json');
      await storageFile.writeAsString('{"saved_key": "user_secret_data"}');

      final userCustomData = File('${sandboxDir.path}/data/records.txt');
      await userCustomData.parent.create(recursive: true);
      await userCustomData.writeAsString('important user notes');

      // 3. 安装 2.0.0 版本进行同名覆盖更新
      final v2PtxBytes = buildPtx({
        'plugin.json': utf8Bytes('{"id":"upgrade_demo","name":"Upgrade Demo",'
            '"version":"2.0.0","description":"v2","author":"a","type":"lua",'
            '"category":"utility","entry":"main.lua","ui":"ui/main.ui.json"}'),
        'main.lua': utf8Bytes('print("v2")'),
        'ui/main.ui.json': utf8Bytes('{"type":"Column","children":[]}'),
      });
      final v2File = await writeTempPtx(v2PtxBytes);
      final pluginV2 = await PluginInstaller.installFromPtx(
        v2File,
        baseDirectory: baseDir,
      );

      // 4. 校验核心代码升级至 2.0.0 且用户历史数据完整无损保留
      expect(pluginV2.manifest.version, '2.0.0');
      final newMainLua =
          await File('${sandboxDir.path}/main.lua').readAsString();
      expect(newMainLua, 'print("v2")');

      expect(await storageFile.exists(), isTrue);
      final restoredStorage = await storageFile.readAsString();
      expect(restoredStorage, contains('user_secret_data'));

      expect(await userCustomData.exists(), isTrue);
      final restoredCustom = await userCustomData.readAsString();
      expect(restoredCustom, 'important user notes');

      await baseDir.delete(recursive: true);
      await v1File.parent.delete(recursive: true);
      await v2File.parent.delete(recursive: true);
    });
  });
}
