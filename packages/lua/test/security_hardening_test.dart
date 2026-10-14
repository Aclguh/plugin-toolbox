import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:lua_dardo/lua.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';
import 'package:plugin_toolbox_lua/plugin_toolbox_lua.dart';

import 'lua_engine_test.dart' show InMemoryPluginStorage, MockLuaHostDelegate;

/// 安全加固回归测试：仅验证宿主 API 绑定、沙箱隔离与权限门控，
/// 不涉及任何插件业务逻辑。
void main() {
  PluginContext buildContext(
    Directory? rootDir,
    Set<PluginPermission> permissions, {
    int storageQuotaMb = 50,
    List<String>? allowedDomains,
  }) {
    return PluginContext(
      pluginId: 'security_test',
      storage: InMemoryPluginStorage(),
      eventBus: EventBusImpl(),
      logger: Logger(),
      grantedPermissions: permissions,
      rootDir: rootDir,
      storageQuotaMb: storageQuotaMb,
      allowedDomains: allowedDomains,
    );
  }

  List<int> buildZip(Map<String, List<int>> files) {
    final archive = Archive();
    files.forEach((name, content) {
      archive.addFile(ArchiveFile(name, content.length, content));
    });
    return ZipEncoder().encode(archive)!;
  }

  group('fs 受保护清单归一化防护', () {
    late MockLuaHostDelegate delegate;
    late Directory tempDir;

    setUp(() {
      delegate = MockLuaHostDelegate();
      tempDir = Directory.systemTemp.createTempSync('ptx_fs_prot_');
      File('${tempDir.path}/plugin.json')
          .writeAsStringSync('ORIGINAL_MANIFEST');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    LuaEngine buildFsEngine() => LuaEngine(
          context: buildContext(tempDir, {PluginPermission.storage}),
          delegate: delegate,
        );

    test('"./plugin.json" 等归一化变体覆写清单全部被拒绝', () {
      final engine = buildFsEngine();
      addTearDown(engine.close);

      // 基线：等值路径仍然拦截
      expect(
        () => engine.loadAndExecute('fs.writeFile("plugin.json", "evil")'),
        throwsException,
      );
      // 归一化绕过变体：./ 前缀
      expect(
        () => engine.loadAndExecute('fs.writeFile("./plugin.json", "evil")'),
        throwsException,
      );
      expect(
        () => engine.loadAndExecute('fs.writeHex("./manifest.json", "4142")'),
        throwsException,
      );
      expect(
        () => engine
            .loadAndExecute('fs.writeBase64("./plugin.json", "ZXZpbA==")'),
        throwsException,
      );
      expect(
        () => engine.loadAndExecute('fs.remove("./plugin.json")'),
        throwsException,
      );

      // copy / move 的目标路径同样受保护
      engine.loadAndExecute('fs.writeFile("a.txt", "data")');
      expect(
        () => engine.loadAndExecute('fs.copy("a.txt", "./plugin.json")'),
        throwsException,
      );
      expect(
        () => engine.loadAndExecute('fs.move("a.txt", "./manifest.json")'),
        throwsException,
      );

      // 清单原件未被篡改
      expect(File('${tempDir.path}/plugin.json').readAsStringSync(),
          'ORIGINAL_MANIFEST');
    });

    test('异步写接口的归一化变体经回调拒绝且不落盘', () async {
      final engine = buildFsEngine();
      addTearDown(engine.close);

      engine.loadAndExecute('''
        fs.writeFile("./plugin.json", "evil", function(ok, err)
          state.set("wf_ok", ok)
          state.set("wf_err", err)
        end)
        fs.writeFileAsync("./manifest.json", "evil", function(ok, err)
          state.set("wfa_ok", ok)
          state.set("wfa_err", err)
        end)
      ''');

      await pumpEventQueue();
      expect(delegate.getState('wf_ok'), false);
      expect(delegate.getState('wf_err'), contains('受保护'));
      expect(delegate.getState('wfa_ok'), false);
      expect(delegate.getState('wfa_err'), contains('受保护'));
      expect(File('${tempDir.path}/plugin.json').readAsStringSync(),
          'ORIGINAL_MANIFEST');
    });

    test('子目录中的同名普通文件不误伤 (不过度拦截)', () {
      final engine = buildFsEngine();
      addTearDown(engine.close);

      engine.loadAndExecute('''
        state.set("sub_write_ok", fs.writeFile("sub/plugin.json", "nested"))
        state.set("sub_read", fs.readFile("sub/plugin.json"))
      ''');

      expect(delegate.getState('sub_write_ok'), true);
      expect(delegate.getState('sub_read'), 'nested');
      expect(File('${tempDir.path}/plugin.json').readAsStringSync(),
          'ORIGINAL_MANIFEST');
    });

    test('沙箱内符号链接指向外部目标时被拦截拒绝', () {
      final engine = buildFsEngine();
      addTearDown(engine.close);

      final outsideFile = File(
          '${tempDir.parent.path}/outside_secret_${DateTime.now().microsecondsSinceEpoch}.txt')
        ..writeAsStringSync('OUTSIDE_SECRET');
      addTearDown(() {
        if (outsideFile.existsSync()) outsideFile.deleteSync();
      });

      try {
        final link = Link('${tempDir.path}/symlink_escape');
        link.createSync(outsideFile.path);

        expect(
          () => engine.loadAndExecute('fs.readFile("symlink_escape")'),
          throwsA(isA<Exception>().having(
            (e) => e.toString(),
            'error',
            contains('逃逸沙箱'),
          )),
        );
      } on FileSystemException {
        // Windows 环境下未开启开发者模式可能无权创建符号链接，安全放行
      }
    });
  });

  group('沙箱字节码逃逸面封禁', () {
    late MockLuaHostDelegate delegate;
    late LuaEngine engine;

    setUp(() {
      delegate = MockLuaHostDelegate();
      engine = LuaEngine(
        context: buildContext(null, {PluginPermission.storage}),
        delegate: delegate,
      );
    });

    tearDown(() {
      engine.close();
    });

    test('load / loadstring / string.dump 全部置 nil', () {
      engine.loadAndExecute('''
        state.set("load_type", type(load))
        state.set("loadstring_type", type(loadstring))
        state.set("dump_type", type(string.dump))
        state.set("upper_type", type(string.upper))
      ''');

      expect(delegate.getState('load_type'), 'nil');
      expect(delegate.getState('loadstring_type'), 'nil');
      expect(delegate.getState('dump_type'), 'nil');
      // 安全字符串函数保持可用
      expect(delegate.getState('upper_type'), 'function');
    });

    test('load 与 string.dump 不可调用并降级为执行错误', () {
      expect(
        () => engine.loadAndExecute('load("return 1")'),
        throwsException,
      );
      expect(
        () => engine.loadAndExecute('string.dump(function() end)'),
        throwsException,
      );
    });
  });

  group('archive.unzip 限额与配额防护', () {
    late MockLuaHostDelegate delegate;
    late Directory tempDir;

    setUp(() {
      delegate = MockLuaHostDelegate();
      tempDir = Directory.systemTemp.createTempSync('ptx_unzip_guard_');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    test('解压总大小超出沙箱配额即整体拒绝且不落盘', () {
      // 1MB 配额下塞入 2MB 高压缩比内容
      File('${tempDir.path}/bomb.zip').writeAsBytesSync(
        buildZip({'big.bin': Uint8List(2 * 1024 * 1024)}),
      );
      final engine = LuaEngine(
        context: buildContext(tempDir, {PluginPermission.storage},
            storageQuotaMb: 1),
        delegate: delegate,
      );
      addTearDown(engine.close);

      engine.loadAndExecute('''
        local ok, err = archive.unzip("bomb.zip", "out")
        state.set("unzip_ok", ok)
        state.set("unzip_err", err)
      ''');

      expect(delegate.getState('unzip_ok'), false);
      expect(delegate.getState('unzip_err') as String, contains('配额'));
      expect(Directory('${tempDir.path}/out').existsSync(), isFalse);
    });

    test('膨胀比超限判定为 zip bomb 并拒绝', () {
      // 50MB 配额下 5MB 零字节内容压缩至数 KB，膨胀比约千倍
      File('${tempDir.path}/ratio.zip').writeAsBytesSync(
        buildZip({'zeros.bin': Uint8List(5 * 1024 * 1024)}),
      );
      final engine = LuaEngine(
        context: buildContext(tempDir, {PluginPermission.storage}),
        delegate: delegate,
      );
      addTearDown(engine.close);

      engine.loadAndExecute('''
        local ok, err = archive.unzip("ratio.zip", "out")
        state.set("unzip_ok", ok)
        state.set("unzip_err", err)
      ''');

      expect(delegate.getState('unzip_ok'), false);
      expect(delegate.getState('unzip_err') as String, contains('膨胀比'));
      expect(Directory('${tempDir.path}/out').existsSync(), isFalse);
    });

    test('条目数超限拒绝', () {
      final files = <String, List<int>>{};
      for (var i = 0; i < 1001; i++) {
        files['f$i.txt'] = Uint8List(1);
      }
      File('${tempDir.path}/many.zip').writeAsBytesSync(buildZip(files));
      final engine = LuaEngine(
        context: buildContext(tempDir, {PluginPermission.storage}),
        delegate: delegate,
      );
      addTearDown(engine.close);

      engine.loadAndExecute('''
        local ok, err = archive.unzip("many.zip", "out")
        state.set("unzip_ok", ok)
        state.set("unzip_err", err)
      ''');

      expect(delegate.getState('unzip_ok'), false);
      expect(delegate.getState('unzip_err') as String, contains('条目数'));
    });

    test('解压至根目录时受保护清单条目被跳过、普通条目正常落盘', () {
      File('${tempDir.path}/plugin.json')
          .writeAsStringSync('ORIGINAL_MANIFEST');
      File('${tempDir.path}/pkg.zip').writeAsBytesSync(buildZip({
        'plugin.json': Uint8List.fromList('evil'.codeUnits),
        'data.txt': Uint8List.fromList('good'.codeUnits),
      }));
      final engine = LuaEngine(
        context: buildContext(tempDir, {PluginPermission.storage}),
        delegate: delegate,
      );
      addTearDown(engine.close);

      engine.loadAndExecute('''
        local ok = archive.unzip("pkg.zip", ".")
        state.set("unzip_ok", ok)
      ''');

      expect(delegate.getState('unzip_ok'), true);
      expect(File('${tempDir.path}/plugin.json').readAsStringSync(),
          'ORIGINAL_MANIFEST');
      expect(File('${tempDir.path}/data.txt').readAsStringSync(), 'good');
    });
  });

  group('network 重定向逐跳校验与响应体上限', () {
    late MockLuaHostDelegate delegate;
    late HttpServer server;
    late String base;
    late LuaEngine engine;

    setUp(() async {
      delegate = MockLuaHostDelegate();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      base = 'http://127.0.0.1:${server.port}';
      final bigBody = Uint8List(10 * 1024 * 1024 + 1);
      server.listen((HttpRequest req) {
        final res = req.response;
        switch (req.uri.path) {
          case '/ok':
            res.statusCode = 200;
            res.write('ok-body');
            res.close();
            break;
          case '/redirect-ok':
            res.statusCode = 302;
            res.headers.set('location', '/ok');
            res.close();
            break;
          case '/redirect-evil':
            res.statusCode = 302;
            res.headers.set('location', 'http://localhost:${server.port}/ok');
            res.close();
            break;
          case '/loop':
            res.statusCode = 302;
            res.headers.set('location', '/loop');
            res.close();
            break;
          case '/big':
            res.statusCode = 200;
            res.add(bigBody);
            res.close();
            break;
          default:
            res.statusCode = 404;
            res.close();
        }
      });
      engine = LuaEngine(
        context: buildContext(null, {PluginPermission.network},
            allowedDomains: ['127.0.0.1']),
        delegate: delegate,
      );
    });

    tearDown(() async {
      engine.close();
      await server.close(force: true);
    });

    test('白名单内的同域重定向被正常跟随', () async {
      engine.loadAndExecute('''
        network.get("$base/redirect-ok", function(res)
          state.set("r_ok", res.ok)
          state.set("r_body", res.body)
        end)
      ''');

      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(delegate.getState('r_ok'), true);
      expect(delegate.getState('r_body'), 'ok-body');
    });

    test('重定向至白名单外域名被逐跳校验拦截', () async {
      engine.loadAndExecute('''
        network.get("$base/redirect-evil", function(res)
          state.set("e_ok", res.ok)
          state.set("e_err", res.error)
        end)
      ''');

      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(delegate.getState('e_ok'), false);
      expect(delegate.getState('e_err') as String, contains('白名单'));
    });

    test('重定向跳数超限被中止', () async {
      engine.loadAndExecute('''
        network.get("$base/loop", function(res)
          state.set("l_ok", res.ok)
          state.set("l_err", res.error)
        end)
      ''');

      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(delegate.getState('l_ok'), false);
      expect(delegate.getState('l_err') as String, contains('重定向跳数超限'));
    });

    test('响应体超出 10MB 上限被拒绝', () async {
      engine.loadAndExecute('''
        network.get("$base/big", function(res)
          state.set("b_ok", res.ok)
          state.set("b_err", res.error)
        end)
      ''');

      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(delegate.getState('b_ok'), false);
      expect(delegate.getState('b_err') as String, contains('大小上限'));
    });

    test('常规请求与 POST 重定向改写 GET 语义保持可用', () async {
      engine.loadAndExecute('''
        network.get("$base/ok", function(res)
          state.set("g_ok", res.ok)
          state.set("g_body", res.body)
        end)
        network.post("$base/redirect-ok", "{}", function(res)
          state.set("p_ok", res.ok)
          state.set("p_body", res.body)
        end)
      ''');

      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(delegate.getState('g_ok'), true);
      expect(delegate.getState('g_body'), 'ok-body');
      expect(delegate.getState('p_ok'), true);
      expect(delegate.getState('p_body'), 'ok-body');
    });
  });

  group('database 沙箱挂载与权限门控', () {
    late MockLuaHostDelegate delegate;

    setUp(() {
      delegate = MockLuaHostDelegate();
    });

    test('rootDir 缺失时显式抛错降级而非写 CWD', () {
      final engine = LuaEngine(
        context: buildContext(null, {PluginPermission.database}),
        delegate: delegate,
      );
      addTearDown(engine.close);

      expect(
        () => engine.loadAndExecute('db.execute("CREATE TABLE t (id)")'),
        throwsException,
      );
      expect(
        () => engine.loadAndExecute('db.query("SELECT * FROM t")'),
        throwsException,
      );
      // CWD 下不得生成退化库文件
      expect(File('plugin_data_security_test.db').existsSync(), isFalse);
    });

    test('仅 storage 权限不再解锁 database', () {
      final tempDir = Directory.systemTemp.createTempSync('ptx_db_perm_');
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });
      final engine = LuaEngine(
        context: buildContext(tempDir, {PluginPermission.storage}),
        delegate: delegate,
      );
      addTearDown(engine.close);

      expect(
        () => engine.loadAndExecute('db.execute("CREATE TABLE t (id)")'),
        throwsException,
      );
    });

    test('引擎 rename 覆盖落盘不预删主文件且数据完整', () async {
      final tempDir = Directory.systemTemp.createTempSync('ptx_db_rename_');
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });
      final dbFile = File('${tempDir.path}/plugin_data.db');
      final engine = SandboxDatabaseEngine(dbFile: dbFile);
      addTearDown(engine.dispose);

      await engine.execute('CREATE TABLE t (id)', []);
      await engine.execute('INSERT INTO t (id) VALUES (?)', [1]);
      var res = await engine.flush();
      expect(res['ok'], isTrue);
      expect(dbFile.existsSync(), isTrue);

      // 第二次落盘：rename 直接覆盖既有主文件
      await engine.execute('INSERT INTO t (id) VALUES (?)', [2]);
      res = await engine.flush();
      expect(res['ok'], isTrue);
      expect(dbFile.existsSync(), isTrue);
      expect(File('${dbFile.path}.bak').existsSync(), isTrue);

      final reader = SandboxDatabaseEngine(dbFile: dbFile);
      addTearDown(reader.dispose);
      final q = await reader.query('SELECT COUNT(*) AS c FROM t', []);
      expect((q['rows'] as List).first['c'], 2);
    });
  });

  group('权限门控对齐', () {
    late MockLuaHostDelegate delegate;

    setUp(() {
      delegate = MockLuaHostDelegate();
    });

    test('system.setKeepScreenOn/setBrightness 无 screen 权限被拒绝', () {
      final engine = LuaEngine(
        context: buildContext(null, {PluginPermission.storage}),
        delegate: delegate,
      );
      addTearDown(engine.close);

      expect(
        () => engine.loadAndExecute('system.setKeepScreenOn(true)'),
        throwsException,
      );
      expect(
        () => engine.loadAndExecute('system.setBrightness(0.5)'),
        throwsException,
      );
    });

    test('system 屏幕写操作有 screen 权限时委派宿主', () async {
      final engine = LuaEngine(
        context: buildContext(null, {PluginPermission.screen}),
        delegate: delegate,
      );
      addTearDown(engine.close);

      engine.loadAndExecute('''
        system.setKeepScreenOn(true)
        system.setBrightness(0.6)
      ''');

      await pumpEventQueue();
      expect(delegate.keepScreenOn, isTrue);
      expect(delegate.screenBrightness, 0.6);
    });

    test('media.pickFile 无 storage 权限被拒绝', () {
      final engine = LuaEngine(
        context: buildContext(null, {PluginPermission.photoLibrary}),
        delegate: delegate,
      );
      addTearDown(engine.close);

      expect(
        () => engine.loadAndExecute('media.pickFile(function(p) end)'),
        throwsException,
      );
    });
  });

  group('regex ReDoS 静态防护', () {
    late MockLuaHostDelegate delegate;
    late LuaEngine engine;

    setUp(() {
      delegate = MockLuaHostDelegate();
      engine = LuaEngine(
        context: buildContext(null, {}),
        delegate: delegate,
      );
    });

    tearDown(() {
      engine.close();
    });

    test('嵌套量词模式被拒绝', () {
      expect(
        () => engine.loadAndExecute('regex.test("(a+)+\$", "aaaaaaaaaaaab")'),
        throwsException,
      );
      expect(
        () => engine.loadAndExecute('regex.findAll("(\\\\d*)*", "123")'),
        throwsException,
      );
    });

    test('超长模式与超长输入被拒绝', () {
      expect(
        () => engine.loadAndExecute('regex.test(string.rep("a", 300), "x")'),
        throwsException,
      );
      expect(
        () =>
            engine.loadAndExecute('regex.test("a", string.rep("a", 1048577))'),
        throwsException,
      );
    });

    test('正常业务正则不受影响', () {
      engine.loadAndExecute('''
        state.set("re_ok", regex.test("^\\\\d+\$", "12345"))
        state.set("re_first", regex.firstMatch("[a-z]+", "123abc456"))
      ''');
      expect(delegate.getState('re_ok'), true);
      expect(delegate.getState('re_first'), 'abc');
    });
  });

  group('timer.setInterval 间隔下限', () {
    test('低于 16ms 的周期被抬升至一帧周期', () async {
      final delegate = MockLuaHostDelegate();
      final engine = LuaEngine(
        context: PluginContext(
          pluginId: 'timer_test',
          storage: InMemoryPluginStorage(),
          eventBus: EventBusImpl(),
          logger: Logger(),
          grantedPermissions: {},
        ),
        delegate: delegate,
      );
      addTearDown(engine.close);

      engine.loadAndExecute('''
        local n = 0
        timer.setInterval(1, function()
          n = n + 1
          state.set("tick", n)
        end)
      ''');

      // 轮询等待首次触发：若未做下限抬升，1ms 间隔几乎立即触发；
      // 抬升至 16ms 后首次触发绝不早于 16ms（只断言下界，避免事件循环抖动误判）
      final sw = Stopwatch()..start();
      while (
          delegate.getState('tick') == null && sw.elapsedMilliseconds < 2000) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      expect(delegate.getState('tick'), isNotNull);
      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(16));
    });
  });

  group('LuaValueCodec 循环引用降级', () {
    test('allowCycles 模式下循环引用压栈降级为 nil 而非抛错', () {
      final ls = LuaState.newState();
      ls.openLibs();

      final cyclic = <String, dynamic>{'v': 1};
      cyclic['self'] = cyclic;
      LuaValueCodec.push(ls, cyclic, null, true);
      final res = LuaValueCodec.readTable(ls, -1) as Map;
      expect(res['v'], 1);
      expect(res['self'], isNull);
    });
  });

  group('NetworkApi SSRF 私有 IP 防护', () {
    test('isPrivateOrLocalHost 正确识别各私有网段与本地主机', () {
      expect(NetworkApi.isPrivateOrLocalHost('localhost'), isTrue);
      expect(NetworkApi.isPrivateOrLocalHost('sub.localhost'), isTrue);
      expect(NetworkApi.isPrivateOrLocalHost('service.local'), isTrue);
      expect(NetworkApi.isPrivateOrLocalHost('127.0.0.1'), isTrue);
      expect(NetworkApi.isPrivateOrLocalHost('127.255.255.255'), isTrue);
      expect(NetworkApi.isPrivateOrLocalHost('10.0.0.1'), isTrue);
      expect(NetworkApi.isPrivateOrLocalHost('172.16.0.1'), isTrue);
      expect(NetworkApi.isPrivateOrLocalHost('172.31.255.255'), isTrue);
      expect(NetworkApi.isPrivateOrLocalHost('192.168.1.1'), isTrue);
      expect(NetworkApi.isPrivateOrLocalHost('169.254.169.254'), isTrue);
      expect(NetworkApi.isPrivateOrLocalHost('0.0.0.0'), isTrue);
      expect(NetworkApi.isPrivateOrLocalHost('::1'), isTrue);
      expect(NetworkApi.isPrivateOrLocalHost('fc00::1'), isTrue);

      // 公网地址放行
      expect(NetworkApi.isPrivateOrLocalHost('8.8.8.8'), isFalse);
      expect(NetworkApi.isPrivateOrLocalHost('1.1.1.1'), isFalse);
      expect(NetworkApi.isPrivateOrLocalHost('172.32.0.1'), isFalse);
      expect(NetworkApi.isPrivateOrLocalHost('example.com'), isFalse);
    });

    test('未显式配置私有白名单的插件发起私有 IP 请求被拦截', () async {
      final delegate = MockLuaHostDelegate();
      final engine = LuaEngine(
        context: PluginContext(
          pluginId: 'ssrf_test',
          storage: InMemoryPluginStorage(),
          eventBus: EventBusImpl(),
          logger: Logger(),
          grantedPermissions: {PluginPermission.network},
        ),
        delegate: delegate,
      );
      addTearDown(engine.close);

      engine.loadAndExecute('''
        network.get("http://127.0.0.1:8080/admin", function(res)
          state.set("ssrf_ok", res.ok)
          state.set("ssrf_err", res.error)
        end)
      ''');

      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(delegate.getState('ssrf_ok'), isFalse);
      expect(delegate.getState('ssrf_err').toString(), contains('SSRF 防护'));
    });

    test('DNS 解析至私网 IP 时被拦截 (DNS Rebinding 防护)', () async {
      final prevDnsLookup = NetworkApi.dnsLookup;
      addTearDown(() => NetworkApi.dnsLookup = prevDnsLookup);
      NetworkApi.dnsLookup = (host) async {
        if (host == 'rebind.attacker.com') {
          return [InternetAddress('127.0.0.1')];
        }
        return prevDnsLookup(host);
      };

      final delegate = MockLuaHostDelegate();
      final engine = LuaEngine(
        context: PluginContext(
          pluginId: 'rebind_test',
          storage: InMemoryPluginStorage(),
          eventBus: EventBusImpl(),
          logger: Logger(),
          grantedPermissions: {PluginPermission.network},
        ),
        delegate: delegate,
      );
      addTearDown(engine.close);

      engine.loadAndExecute('''
        network.get("http://rebind.attacker.com:8080/secret", function(res)
          state.set("rebind_ok", res.ok)
          state.set("rebind_err", res.error)
        end)
      ''');

      final sw = Stopwatch()..start();
      while (delegate.getState('rebind_ok') == null &&
          sw.elapsedMilliseconds < 2000) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(delegate.getState('rebind_ok'), isFalse);
      expect(delegate.getState('rebind_err').toString(),
          contains('DNS Rebinding 防护'));
    });
  });

  group('Lua 虚拟机堆内存上限保护', () {
    test('小内存操作正常执行且 allocatedBytes 递增', () {
      final delegate = MockLuaHostDelegate();
      final engine = LuaEngine(
        context: buildContext(null, {}),
        delegate: delegate,
        memoryBudget: 1024 * 1024, // 1MB
      );
      addTearDown(engine.close);

      engine.loadAndExecute('''
        local t = {}
        for i = 1, 50 do
          t["key_" .. i] = "val_" .. i
        end
        return #t
      ''');
      expect(engine.allocatedBytes, greaterThan(0));
      expect(engine.allocatedBytes, lessThan(1024 * 1024));
    });

    test('单实例内存分配超出上限抛出异常并由 pCall 安全捕获', () {
      final delegate = MockLuaHostDelegate();
      // 设置极小堆内存预算：10KB
      final engine = LuaEngine(
        context: buildContext(null, {}),
        delegate: delegate,
        memoryBudget: 10 * 1024,
      );
      addTearDown(engine.close);

      // 构造大字符串或巨型 Table 超出 10KB 限制
      expect(
        () => engine.loadAndExecute('''
          local s = "abcdefghijklmnopqrstuvwxyz"
          for i = 1, 20 do
            s = s .. s
          end
        '''),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'error',
          contains('LuaMemoryLimitException'),
        )),
      );
    });
  });
}
