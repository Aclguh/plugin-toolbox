import 'dart:io';
export 'helpers/lua_test_helpers.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';
import 'package:plugin_toolbox_lua/plugin_toolbox_lua.dart';

import 'helpers/lua_test_helpers.dart';

void main() {
  group('LuaEngine & Host APIs', () {
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
          PluginPermission.storage
        },
      );
      engine = LuaEngine(context: context, delegate: delegate);
    });

    tearDown(() {
      engine.close();
    });

    test('state get and set from Lua', () {
      engine.loadAndExecute('''
        state.set("message", "Hello Lua")
        val = state.get("message")
      ''');

      expect(delegate.getState('message'), 'Hello Lua');
    });

    test('codec 与 hash 宿主 API 以全局表形式绑定注入 (仅验证绑定, 不验证业务结果)', () {
      engine.loadAndExecute('''
        state.set("codec_type", type(codec))
        state.set("codec_encode_fn", type(codec.base64Encode))
        state.set("codec_decode_fn", type(codec.base64Decode))
        state.set("codec_url_fn", type(codec.urlEncode))
        state.set("hash_type", type(hash))
        state.set("hash_md5_fn", type(hash.md5))
        state.set("hash_sha1_fn", type(hash.sha1))
        state.set("hash_sha256_fn", type(hash.sha256))
      ''');

      expect(delegate.getState('codec_type'), 'table');
      expect(delegate.getState('codec_encode_fn'), 'function');
      expect(delegate.getState('codec_decode_fn'), 'function');
      expect(delegate.getState('codec_url_fn'), 'function');
      expect(delegate.getState('hash_type'), 'table');
      expect(delegate.getState('hash_md5_fn'), 'function');
      expect(delegate.getState('hash_sha1_fn'), 'function');
      expect(delegate.getState('hash_sha256_fn'), 'function');
    });

    test('CodecApi 扩展功能: Hex, HexDump, JWT, HTML 实体与 Punycode 编解码', () {
      engine.loadAndExecute('''
        -- Hex
        local hex = codec.hexEncode("Hello")
        local text = codec.hexDecode(hex)
        state.set("hex", hex)
        state.set("hex_text", text)

        -- HexDump
        local dump = codec.hexDump("Hello World! 123")
        state.set("dump", dump)

        -- JWT
        local fakeJwt = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkFsaWNlIiwiYWRtaW4iOnRydWV9.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c"
        local jwt = codec.jwtDecode(fakeJwt)
        state.set("jwt_sub", jwt.payload.sub)
        state.set("jwt_name", jwt.payload.name)
        state.set("jwt_alg", jwt.header.alg)

        -- HTML Entities
        local rawHtml = "<script>alert('Hello & welcome!');</script>"
        local encodedHtml = codec.htmlEntitiesEncode(rawHtml)
        local decodedHtml = codec.htmlEntitiesDecode(encodedHtml)
        state.set("encoded_html", encodedHtml)
        state.set("decoded_html", decodedHtml)

        -- Punycode
        local domain = "测试.com"
        local punyDomain = codec.punycodeEncode(domain)
        local restoredDomain = codec.punycodeDecode(punyDomain)
        state.set("puny_domain", punyDomain)
        state.set("restored_domain", restoredDomain)
      ''');

      expect(delegate.getState('hex'), '48656c6c6f');
      expect(delegate.getState('hex_text'), 'Hello');
      expect((delegate.getState('dump') as String).contains('48 65 6c 6c 6f'),
          isTrue);
      expect(delegate.getState('jwt_sub'), '1234567890');
      expect(delegate.getState('jwt_name'), 'Alice');
      expect(delegate.getState('jwt_alg'), 'HS256');
      expect(
          (delegate.getState('encoded_html') as String)
              .contains('&lt;script&gt;'),
          isTrue);
      expect(delegate.getState('decoded_html'),
          "<script>alert('Hello & welcome!');</script>");
      expect(delegate.getState('puny_domain'), 'xn--0zwm56d.com');
      expect(delegate.getState('restored_domain'), '测试.com');
    });

    test('宿主 API 参数类型错误被隔离为 Lua 执行错误 (不逃逸宿主)', () {
      expect(
        () => engine.loadAndExecute('codec.base64Encode(nil)'),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('Lua 执行错误'),
        )),
      );
    });

    test('system 宿主 API 以全局表形式绑定注入 (仅验证绑定, 不验证设备相关取值)', () {
      engine.loadAndExecute('''
        state.set("system_type", type(system))
        state.set("system_platform_fn", type(system.platform))
        state.set("system_os_version_fn", type(system.osVersion))
        state.set("system_hostname_fn", type(system.hostname))
        state.set("system_cores_fn", type(system.cores))
        state.set("system_locale_fn", type(system.locale))
        state.set("system_screen_w_fn", type(system.screenWidth))
        state.set("system_screen_h_fn", type(system.screenHeight))
        state.set("system_pixel_ratio_fn", type(system.pixelRatio))
        state.set("system_brightness_fn", type(system.brightness))
      ''');

      expect(delegate.getState('system_type'), 'table');
      expect(delegate.getState('system_platform_fn'), 'function');
      expect(delegate.getState('system_os_version_fn'), 'function');
      expect(delegate.getState('system_hostname_fn'), 'function');
      expect(delegate.getState('system_cores_fn'), 'function');
      expect(delegate.getState('system_locale_fn'), 'function');
      expect(delegate.getState('system_screen_w_fn'), 'function');
      expect(delegate.getState('system_screen_h_fn'), 'function');
      expect(delegate.getState('system_pixel_ratio_fn'), 'function');
      expect(delegate.getState('system_brightness_fn'), 'function');
    });

    test('callFunction invokes Lua functions', () {
      engine.loadAndExecute('''
        function add(a, b)
          return a + b
        end
      ''');

      final result = engine.callFunction('add', [10, 25]);
      expect(result, 35);
    });
  });

  group('Lua 沙箱安全与执行防护', () {
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
          PluginPermission.storage
        },
      );
      engine = LuaEngine(context: context, delegate: delegate);
    });

    tearDown(() {
      engine.close();
    });

    test('危险标准库全局全部被置空且 require 受沙箱安全管控', () {
      engine.loadAndExecute('''
        state.set("os_type", type(os))
        state.set("io_type", type(io))
        state.set("debug_type", type(debug))
        state.set("package_type", type(package))
        state.set("require_type", type(require))
        state.set("dofile_type", type(dofile))
        state.set("loadfile_type", type(loadfile))
      ''');

      expect(delegate.getState('os_type'), 'nil');
      expect(delegate.getState('io_type'), 'nil');
      expect(delegate.getState('debug_type'), 'nil');
      expect(delegate.getState('package_type'), 'nil');
      expect(delegate.getState('require_type'), 'function');
      expect(delegate.getState('dofile_type'), 'nil');
      expect(delegate.getState('loadfile_type'), 'nil');
    });

    group('沙箱受限 require 模块化测试', () {
      late Directory tempPluginDir;

      setUp(() async {
        tempPluginDir =
            await Directory.systemTemp.createTemp('ptx_require_test_');
      });

      tearDown(() async {
        if (await tempPluginDir.exists()) {
          await tempPluginDir.delete(recursive: true);
        }
      });

      test('支持加载沙箱内子模块、点号语法与返回值单例缓存', () async {
        final utilsDir = Directory('${tempPluginDir.path}/utils');
        await utilsDir.create(recursive: true);
        final calcFile = File('${utilsDir.path}/calc.lua');
        await calcFile.writeAsString('''
          local M = {}
          M.tag = "calc_v1"
          function M.add(a, b) return a + b end
          return M
        ''');

        final ctx = PluginContext(
          pluginId: 'mod_test',
          storage: PluginStorageImpl(namespace: 'mod_test'),
          eventBus: EventBusImpl(),
          logger: Logger(),
          grantedPermissions: {},
          rootDir: tempPluginDir,
        );
        final eng = LuaEngine(context: ctx, delegate: delegate);

        eng.loadAndExecute('''
          local calc1 = require("utils.calc")
          local calc2 = require("utils/calc")
          state.set("sum", calc1.add(10, 25))
          state.set("tag", calc2.tag)
          state.set("is_same", calc1 == calc2)
        ''');

        expect(delegate.getState('sum'), 35);
        expect(delegate.getState('tag'), 'calc_v1');
        expect(delegate.getState('is_same'), isTrue);

        eng.close();
      });

      test('拦截越权路径穿越 require 尝试', () async {
        final ctx = PluginContext(
          pluginId: 'mod_test',
          storage: PluginStorageImpl(namespace: 'mod_test'),
          eventBus: EventBusImpl(),
          logger: Logger(),
          grantedPermissions: {},
          rootDir: tempPluginDir,
        );
        final eng = LuaEngine(context: ctx, delegate: delegate);

        expect(
          () => eng.loadAndExecute('require("../secret")'),
          throwsA(isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('安全策略拦截'),
          )),
        );

        eng.close();
      });

      test('拦截预编译字节码模块加载', () async {
        final bytecodeFile = File('${tempPluginDir.path}/evil.lua');
        await bytecodeFile.writeAsBytes([0x1B, 0x4C, 0x75, 0x61, 0x01, 0x02]);

        final ctx = PluginContext(
          pluginId: 'mod_test',
          storage: PluginStorageImpl(namespace: 'mod_test'),
          eventBus: EventBusImpl(),
          logger: Logger(),
          grantedPermissions: {},
          rootDir: tempPluginDir,
        );
        final eng = LuaEngine(context: ctx, delegate: delegate);

        expect(
          () => eng.loadAndExecute('require("evil")'),
          throwsA(isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('安全策略拦截: 模块禁止使用预编译 Lua 字节码'),
          )),
        );

        eng.close();
      });
    });

    test('安全基础库 (table/string/math) 保持可用', () {
      engine.loadAndExecute('''
        local t = {3, 1, 2}
        table.sort(t)
        state.set("first", tostring(t[1]))
        state.set("upper", string.upper("abc"))
        state.set("abs", tostring(math.abs(-5)))
      ''');

      expect(delegate.getState('first'), '1');
      expect(delegate.getState('upper'), 'ABC');
      expect(delegate.getState('abs'), '5');
    });

    test('os.execute 不可调用并降级为执行错误', () {
      expect(
        () => engine.loadAndExecute('os.execute("echo pwned")'),
        throwsException,
      );
    });

    test('loadfile 不可调用并降级为执行错误', () {
      expect(
        () => engine.loadAndExecute('loadfile("/etc/passwd")'),
        throwsException,
      );
    });

    test('指令数预算阻断死循环', () {
      final limited = LuaEngine(
        context: context,
        delegate: delegate,
        instructionBudget: 5000,
      );
      try {
        expect(
          () => limited.loadAndExecute('while true do end'),
          throwsA(isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('Lua 执行错误'),
          )),
        );
      } finally {
        limited.close();
      }
    });

    test('包含循环引用的集合压栈被拒绝', () {
      engine.loadAndExecute('function sink(v) return 1 end');
      final cyclic = <String, dynamic>{'k': 'v'};
      cyclic['self'] = cyclic;
      expect(() => engine.callFunction('sink', [cyclic]), throwsException);
    });

    test('Lua 侧包含循环引用的表出栈被安全截断，不发生栈溢出', () {
      engine.loadAndExecute('''
        function getCyclic()
          local a = { name = "root" }
          a.self = a
          return a
        end
      ''');
      final res = engine.callFunction('getCyclic');
      expect(res, isA<Map>());
      expect((res as Map)['name'], 'root');
      expect(res['self'], isNull);
    });
  });

  group('Lua 异步宿主 API', () {
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
          PluginPermission.storage
        },
      );
      engine = LuaEngine(context: context, delegate: delegate);
    });

    tearDown(() {
      engine.close();
    });

    test('clipboard.set 写入文本至剪贴板委托', () {
      engine.loadAndExecute('''
        clipboard.set("hello-clipboard-text")
      ''');
      expect(delegate.clipboardContent, 'hello-clipboard-text');
    });

    test('clipboard.get 通过回调异步返回剪贴板文本', () async {
      delegate.setClipboardText('mock-clipboard-text');

      engine.loadAndExecute('''
        clipboard.get(function(val) state.set("clip_value", val) end)
      ''');

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(delegate.getState('clip_value'), 'mock-clipboard-text');
    });

    test('storage.get 通过回调返回已存储的值', () async {
      engine.loadAndExecute('''
        storage.set("k1", "v1")
        storage.get("k1", function(val) state.set("got", val) end)
      ''');

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(delegate.getState('got'), 'v1');
    });

    test('storage.remove 删除后 get 回调收到 nil', () async {
      engine.loadAndExecute('''
        storage.set("k2", "v2")
        storage.remove("k2")
        storage.get("k2", function(val) state.set("got_nil", val == nil) end)
      ''');

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(delegate.getState('got_nil'), true);
    });

    test('dialog.confirm 异步携带用户选择回调', () async {
      engine.loadAndExecute('''
        dialog.confirm("标题", "内容", function(ok) state.set("confirmed", ok) end)
      ''');

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(delegate.getState('confirmed'), true);
    });

    test('dialog.pickDate 与 dialog.pickTime 支持回调与状态写入', () async {
      engine.loadAndExecute('''
        dialog.pickDate(function(d)
          state.set("cb_date", d)
        end)
        dialog.pickTime(function(t)
          state.set("cb_time", t)
        end)
        dialog.pickDate("2024-01-01")
        dialog.pickTime("12:00")
      ''');

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(delegate.getState('cb_date'), '2025-06-15');
      expect(delegate.getState('cb_time'), '15:45');
      expect(delegate.getState('__dialog_date'), '2025-06-15');
      expect(delegate.getState('__dialog_time'), '15:45');
    });

    test('未声明 network 权限时 network.get 直接报错', () {
      expect(
        () => engine.loadAndExecute('network.get("http://example.com")'),
        throwsException,
      );
    });

    test('Lua 表连续整数索引被识别为 List 数组 (P2-2)', () {
      engine.loadAndExecute('''
        function get_array()
          return {10, 20, 30}
        end
        function get_nested_array()
          return { {1, 2}, {3, 4} }
        end
        function get_map()
          return { a = 1, b = 2 }
        end
        function get_sparse()
          return { [1] = "first", [3] = "third" }
        end
      ''');

      final arrayResult = engine.callFunction('get_array');
      expect(arrayResult, isA<List>());
      expect(arrayResult, [10, 20, 30]);

      final nestedResult = engine.callFunction('get_nested_array');
      expect(nestedResult, isA<List>());
      expect(nestedResult, [
        [1, 2],
        [3, 4],
      ]);

      final mapResult = engine.callFunction('get_map');
      expect(mapResult, isA<Map>());
      expect(mapResult, {'a': 1, 'b': 2});

      // 稀疏表（非连续 1..N）降级为 Map
      final sparseResult = engine.callFunction('get_sparse');
      expect(sparseResult, isA<Map>());
      expect(sparseResult, {'1': 'first', '3': 'third'});
    });

    test('宿主 API 懒绑定机制：低频/重型模块按需触发加载', () {
      // 核心 API 默认已绑定
      expect(engine.isModuleBound('state'), isTrue);
      expect(engine.isModuleBound('clipboard'), isTrue);
      expect(engine.isModuleBound('codec'), isTrue);

      // 低频模块初始处于未绑定状态
      expect(engine.isModuleBound('crypto'), isFalse);
      expect(engine.isModuleBound('network'), isFalse);
      expect(engine.isModuleBound('qrcode'), isFalse);

      // 访问 crypto 模块，触发按需加载并自动缓存
      engine.loadAndExecute('local c = crypto');
      expect(engine.isModuleBound('crypto'), isTrue);
      expect(engine.isModuleBound('network'), isFalse);

      // bindAll 显式全量绑定
      engine.bindAll();
      expect(engine.isModuleBound('network'), isTrue);
      expect(engine.isModuleBound('qrcode'), isTrue);
    });

    test('LuaEngine.close() 幂等且禁止在关闭后继续调用 (P2-5)', () {
      expect(engine.isClosed, isFalse);
      engine.close();
      expect(engine.isClosed, isTrue);

      // 再次调用 close 幂等不崩溃
      expect(() => engine.close(), returnsNormally);

      // 关闭后调用执行方法抛出 StateError
      expect(
        () => engine.loadAndExecute('print("hello")'),
        throwsA(isA<StateError>()),
      );
      expect(
        () => engine.callFunction('non_existent'),
        throwsA(isA<StateError>()),
      );
    });
  });
}
