import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';
import 'package:plugin_toolbox_lua/plugin_toolbox_lua.dart';

class MockLuaHostDelegate implements LuaHostDelegate {
  final Map<String, dynamic> state = {};
  final List<String> toasts = [];

  @override
  void onStateChanged(String key, dynamic value) {
    state[key] = value;
  }

  @override
  dynamic getState(String key) => state[key];

  @override
  Map<String, dynamic> getAllStates() => Map.unmodifiable(state);

  @override
  void showToast(String message) {
    toasts.add(message);
  }

  @override
  Future<void> showAlert(String title, String message) async {}

  @override
  Future<bool> showConfirm(String title, String message) async => true;
}

class InMemoryPluginStorage implements PluginStorage {
  final Map<String, dynamic> _data = {};

  @override
  Future<String?> getString(String key) async => _data[key] as String?;

  @override
  Future<bool> setString(String key, String value) async {
    _data[key] = value;
    return true;
  }

  @override
  Future<bool?> getBool(String key) async => _data[key] as bool?;

  @override
  Future<bool> setBool(String key, bool value) async {
    _data[key] = value;
    return true;
  }

  @override
  Future<int?> getInt(String key) async => _data[key] as int?;

  @override
  Future<bool> setInt(String key, int value) async {
    _data[key] = value;
    return true;
  }

  @override
  Future<double?> getDouble(String key) async => _data[key] as double?;

  @override
  Future<bool> setDouble(String key, double value) async {
    _data[key] = value;
    return true;
  }

  @override
  Future<List<String>?> getStringList(String key) async => _data[key] as List<String>?;

  @override
  Future<bool> setStringList(String key, List<String> value) async {
    _data[key] = value;
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    _data.remove(key);
    return true;
  }

  @override
  Future<bool> clear() async {
    _data.clear();
    return true;
  }
}

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
        grantedPermissions: {PluginPermission.clipboard, PluginPermission.storage},
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
        grantedPermissions: {PluginPermission.clipboard, PluginPermission.storage},
      );
      engine = LuaEngine(context: context, delegate: delegate);
    });

    tearDown(() {
      engine.close();
    });

    test('危险标准库全局全部被置空', () {
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
      expect(delegate.getState('require_type'), 'nil');
      expect(delegate.getState('dofile_type'), 'nil');
      expect(delegate.getState('loadfile_type'), 'nil');
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
        grantedPermissions: {PluginPermission.clipboard, PluginPermission.storage},
      );
      engine = LuaEngine(context: context, delegate: delegate);
    });

    tearDown(() {
      engine.close();
    });

    test('clipboard.get 通过回调异步返回剪贴板文本', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      const channel = SystemChannels.platform;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'Clipboard.getData') {
          return <String, dynamic>{'text': 'mock-clipboard-text'};
        }
        return null;
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding.instance
          .defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null));

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

  group('JSON 宿主 API', () {
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
        grantedPermissions: {PluginPermission.clipboard, PluginPermission.storage},
      );
      engine = LuaEngine(context: context, delegate: delegate);
    });

    tearDown(() {
      engine.close();
    });

    test('json 全局表以绑定形式注入 (仅验证绑定, 不验证业务数据)', () {
      engine.loadAndExecute('''
        state.set("json_type", type(json))
        state.set("json_encode_fn", type(json.encode))
        state.set("json_decode_fn", type(json.decode))
      ''');

      expect(delegate.getState('json_type'), 'table');
      expect(delegate.getState('json_encode_fn'), 'function');
      expect(delegate.getState('json_decode_fn'), 'function');
    });

    test('json.encode 将 Lua 表结构序列化为 JSON 字符串', () {
      engine.loadAndExecute('''
        function enc()
          return json.encode({
            hello = "world",
            n = 3,
            arr = {1, 2, 3},
            flag = true,
            nested = { inner = {1, 2} },
          })
        end
      ''');

      final out = engine.callFunction('enc') as String;
      final parsed = jsonDecode(out) as Map<String, dynamic>;
      expect(parsed['hello'], 'world');
      expect(parsed['n'], 3);
      expect(parsed['arr'], [1, 2, 3]);
      expect(parsed['flag'], true);
      expect(parsed['nested'], {'inner': [1, 2]});
    });

    test('json.encode 标量与空表', () {
      engine.loadAndExecute('''
        function enc_scalar()
          return json.encode(42)
        end
        function enc_str()
          return json.encode("hi")
        end
        function enc_empty()
          return json.encode({})
        end
      ''');

      expect(engine.callFunction('enc_scalar'), '42');
      expect(engine.callFunction('enc_str'), '"hi"');
      // 空表无 1..N 数组特征, 统一按对象序列化
      expect(engine.callFunction('enc_empty'), '{}');
    });

    test('json.decode 将 JSON 文本还原为 Lua 表结构', () {
      engine.loadAndExecute('''
        function dec(s)
          return json.decode(s)
        end
      ''');

      // null 值依 Lua 表语义表现为键缺失 (赋 nil 即删除键)
      final obj = engine.callFunction('dec',
          ['{"a":[1,2,{"b":null}],"s":"x","f":1.5,"ok":true}']);
      expect(obj, {
        'a': [1, 2, {}],
        's': 'x',
        'f': 1.5,
        'ok': true,
      });
      expect(engine.callFunction('dec', ['[10,20]']), [10, 20]);
      expect(engine.callFunction('dec', ['null']), isNull);
    });

    test('json.decode 后再 encode 与压缩输入保持结构等价', () {
      engine.loadAndExecute('''
        function roundtrip(s)
          return json.encode(json.decode(s))
        end
      ''');

      expect(
        engine.callFunction('roundtrip', ['{ "a" : [1, 2], "b" : "x" }']),
        '{"a":[1,2],"b":"x"}',
      );
    });

    test('json.encode 循环引用表降级为 Lua 执行错误 (不逃逸宿主)', () {
      engine.loadAndExecute('''
        function makeCyclic()
          local t = {}
          t.self = t
          return json.encode(t)
        end
      ''');

      expect(
        () => engine.callFunction('makeCyclic'),
        throwsA(isA<Exception>().having(
          (e) => e.toString(),
          'message',
          contains('循环引用'),
        )),
      );
    });

    test('json.encode 不可序列化类型与 json.decode 非法输入均被 pcall 隔离', () {
      engine.loadAndExecute('''
        function tryEncodeFn()
          local ok, err = pcall(json.encode, {f = print})
          state.set("enc_ok", ok)
        end
        function tryDecodeBad()
          local ok, err = pcall(json.decode, "{bad json")
          state.set("dec_ok", ok)
        end
      ''');

      engine.callFunction('tryEncodeFn');
      expect(delegate.getState('enc_ok'), false);
      engine.callFunction('tryDecodeBad');
      expect(delegate.getState('dec_ok'), false);
    });

    test('超深嵌套 JSON 在解析前被深度预检拦截', () {
      final deep = ('[' * 100) + (']' * 100);
      engine.loadAndExecute('''
        function tryDeep(s)
          local ok = pcall(json.decode, s)
          state.set("deep_ok", ok)
        end
      ''');

      engine.callFunction('tryDeep', [deep]);
      expect(delegate.getState('deep_ok'), false);
    });

    test('未声明 network 权限时 network.post 直接报错', () {
      expect(
        () => engine.loadAndExecute('network.post("http://example.com", "{}")'),
        throwsException,
      );
    });

    test('network.post 以绑定形式注入 (仅验证绑定)', () {
      engine.loadAndExecute('state.set("post_fn", type(network.post))');
      expect(delegate.getState('post_fn'), 'function');
    });
  });
}
