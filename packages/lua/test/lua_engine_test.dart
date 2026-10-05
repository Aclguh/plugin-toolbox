import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';
import 'package:plugin_toolbox_lua/plugin_toolbox_lua.dart';

class MockLuaHostDelegate implements LuaHostDelegate {
  final Map<String, dynamic> state = {};
  final List<String> toasts = [];
  final List<String> haptics = [];
  bool keyboardHidden = false;
  String? sharedText;
  String? openedUrl;
  String? pickedFileResult;
  String? pickedImageResult;

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

  @override
  void hideKeyboard() {
    keyboardHidden = true;
  }

  @override
  void hapticFeedback(String type) {
    haptics.add(type);
  }

  @override
  Future<void> shareText(String text, {String? subject}) async {
    sharedText = text;
  }

  @override
  Future<bool> openUrl(String url) async {
    openedUrl = url;
    return true;
  }

  @override
  Future<String?> pickFile({List<String>? allowedExtensions}) async =>
      pickedFileResult;

  @override
  Future<String?> pickImage() async => pickedImageResult;

  bool torchState = false;
  String? sharedFilePath;
  String? sharedFileMimeType;
  String? sharedFileSubject;
  String? savedGalleryPath;
  String? exportedFilePath;
  String? exportedFileDefaultName;
  String? mockPickedDate = '2025-06-15';
  String? mockPickedTime = '15:45';

  @override
  Future<bool> setTorch(bool enabled) async {
    torchState = enabled;
    return true;
  }

  @override
  bool get isTorchOn => torchState;

  @override
  Future<bool> shareFile(
    String filePath, {
    String? mimeType,
    String? subject,
  }) async {
    sharedFilePath = filePath;
    sharedFileMimeType = mimeType;
    sharedFileSubject = subject;
    return true;
  }

  @override
  Future<bool> saveToGallery(String filePath) async {
    savedGalleryPath = filePath;
    return true;
  }

  @override
  Future<bool> exportFile(
    String filePath, {
    String? defaultName,
  }) async {
    exportedFilePath = filePath;
    exportedFileDefaultName = defaultName;
    return true;
  }

  @override
  Future<String?> pickDate({
    String? initialDate,
    String? firstDate,
    String? lastDate,
  }) async =>
      mockPickedDate;

  @override
  Future<String?> pickTime({
    String? initialTime,
  }) async =>
      mockPickedTime;
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

    test('HapticApi 触觉反馈调用委派给宿主', () {
      engine.loadAndExecute('''
        haptic.light()
        haptic.medium()
        haptic.heavy()
        haptic.selection()
        haptic.vibrate()
      ''');
      expect(delegate.haptics, ['light', 'medium', 'heavy', 'selection', 'vibrate']);
    });

    test('UiApi 软键盘收起与 Toast 委派给宿主', () {
      engine.loadAndExecute('''
        ui.hideKeyboard()
        ui.toast("测试提示")
      ''');
      expect(delegate.keyboardHidden, true);
      expect(delegate.toasts.contains('测试提示'), true);
    });

    test('ShareApi 文本分享委派给宿主', () {
      engine.loadAndExecute('share.text("分享文本内容", "主题")');
      expect(delegate.sharedText, '分享文本内容');
    });

    test('ShareApi 文件分享防路径穿越并委派宿主', () async {
      final tempDir = Directory.systemTemp.createTempSync('ptx_share_test_');
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });
      final testFile = File('${tempDir.path}/report.csv')
        ..writeAsStringSync('a,b,c');

      final shareCtx = PluginContext(
        pluginId: 'share_test',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {PluginPermission.storage},
        rootDir: tempDir,
      );
      final shareEngine = LuaEngine(context: shareCtx, delegate: delegate);

      // 1. 越界分享拦截
      expect(
        () => shareEngine.loadAndExecute('share.file("../secret.txt")'),
        throwsException,
      );

      // 2. 正常合法文件分享
      shareEngine.loadAndExecute('''
        share.file("report.csv", "text/csv", "分享报表", function(ok)
          state.set("share_ok", ok)
        end)
      ''');

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(delegate.sharedFilePath, testFile.path);
      expect(delegate.sharedFileMimeType, 'text/csv');
      expect(delegate.sharedFileSubject, '分享报表');
      expect(delegate.getState('share_ok'), true);
    });

    test('SystemApi.openUrl 外部链接跳转委派给宿主', () {
      engine.loadAndExecute('system.openUrl("https://example.com")');
      expect(delegate.openedUrl, 'https://example.com');
    });

    test('MediaApi 未声明 photoLibrary 权限时拒绝 pickImage', () {
      expect(
        () => engine.loadAndExecute('media.pickImage()'),
        throwsException,
      );
    });

    test('MediaApi 声明权限后 pickImage 与 pickFile 正常调用', () async {
      final mediaCtx = PluginContext(
        pluginId: 'media_test',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {PluginPermission.photoLibrary, PluginPermission.storage},
      );
      final mediaEngine = LuaEngine(context: mediaCtx, delegate: delegate);
      delegate.pickedImageResult = 'data/test.jpg';
      delegate.pickedFileResult = 'data/doc.pdf';

      mediaEngine.loadAndExecute('''
        media.pickImage(function(path)
          state.set("image_path", path)
        end)
        media.pickFile(function(path)
          state.set("file_path", path)
        end)
      ''');

      await pumpEventQueue();
      expect(delegate.getState('image_path'), 'data/test.jpg');
      expect(delegate.getState('file_path'), 'data/doc.pdf');
    });

    test('TimerApi setTimeout 与 clear', () async {
      engine.loadAndExecute('''
        timer.setTimeout(10, function()
          state.set("timeout_called", true)
        end)
        local toCancel = timer.setTimeout(500, function()
          state.set("cancelled_called", true)
        end)
        timer.clear(toCancel)
      ''');

      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(delegate.getState('timeout_called'), true);
      expect(delegate.getState('cancelled_called'), isNull);
    });

    test('TimerApi clearAll 与 close 自动回收所有定时器', () async {
      engine.loadAndExecute('''
        timer.setTimeout(200, function()
          state.set("never_call", true)
        end)
      ''');
      engine.close();
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(delegate.getState('never_call'), isNull);
    });

    test('FsApi 沙箱文件读写、罗列与路径穿越拦截', () {
      final tempDir = Directory.systemTemp.createTempSync('ptx_fs_test_');
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      final fsCtx = PluginContext(
        pluginId: 'fs_test',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {PluginPermission.storage},
        rootDir: tempDir,
      );
      final fsEngine = LuaEngine(context: fsCtx, delegate: delegate);

      // 1. 路径穿越拦截
      expect(
        () => fsEngine.loadAndExecute('fs.readFile("../../etc/passwd")'),
        throwsException,
      );

      // 2. 正常写入与读取
      fsEngine.loadAndExecute('''
        fs.writeFile("sub/test.txt", "hello sandbox")
        local content = fs.readFile("sub/test.txt")
        state.set("read_content", content)
        state.set("file_exists", fs.exists("sub/test.txt"))
        state.set("not_exists", fs.exists("no_such.txt"))
        
        local stat = fs.stat("sub/test.txt")
        state.set("file_size", stat.size)
        state.set("is_dir", stat.isDirectory)

        local list = fs.listFiles("sub")
        state.set("list_len", #list)
        state.set("list_first", list[1])

        fs.remove("sub/test.txt")
        state.set("after_remove_exists", fs.exists("sub/test.txt"))
      ''');

      expect(delegate.getState('read_content'), 'hello sandbox');
      expect(delegate.getState('file_exists'), true);
      expect(delegate.getState('not_exists'), false);
      expect(delegate.getState('file_size'), 'hello sandbox'.length);
      expect(delegate.getState('is_dir'), false);
      expect(delegate.getState('list_len'), 1);
      expect(delegate.getState('list_first'), 'test.txt');
      expect(delegate.getState('after_remove_exists'), false);
    });

    test('FsApi saveToGallery 与 exportFile 保存与导出', () async {
      final tempDir = Directory.systemTemp.createTempSync('ptx_fs_export_');
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });
      final imgFile = File('${tempDir.path}/pic.png')
        ..writeAsStringSync('fake-png-data');
      final docFile = File('${tempDir.path}/data.csv')
        ..writeAsStringSync('col1,col2');

      final fsCtx = PluginContext(
        pluginId: 'fs_export_test',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {PluginPermission.storage},
        rootDir: tempDir,
      );
      final fsEngine = LuaEngine(context: fsCtx, delegate: delegate);

      // 1. 非图片格式拒绝存入相册
      expect(
        () => fsEngine.loadAndExecute('fs.saveToGallery("data.csv")'),
        throwsException,
      );

      // 2. 正常保存图片到相册
      fsEngine.loadAndExecute('''
        fs.saveToGallery("pic.png", function(ok)
          state.set("gallery_saved", ok)
        end)
      ''');

      // 3. 导出文件到系统
      fsEngine.loadAndExecute('''
        fs.exportFile("data.csv", "my_export.csv", function(ok)
          state.set("exported_ok", ok)
        end)
      ''');

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(delegate.savedGalleryPath, imgFile.path);
      expect(delegate.getState('gallery_saved'), true);
      expect(delegate.exportedFilePath, docFile.path);
      expect(delegate.exportedFileDefaultName, 'my_export.csv');
      expect(delegate.getState('exported_ok'), true);
    });

    test('CryptoApi HMAC 与 SHA512 计算', () {
      engine.loadAndExecute('''
        state.set("h_md5", crypto.hmacMd5("key", "data"))
        state.set("h_sha1", crypto.hmacSha1("key", "data"))
        state.set("h_sha256", crypto.hmacSha256("key", "data"))
        state.set("sha512", crypto.sha512("data"))
      ''');

      expect(delegate.getState('h_md5'), isA<String>());
      expect(delegate.getState('h_sha1'), isA<String>());
      expect(delegate.getState('h_sha256'), isA<String>());
      expect((delegate.getState('sha512') as String).length, 128);
    });

    test('RegexApi 正则匹配、查找与替换', () {
      engine.loadAndExecute('''
        state.set("is_match", regex.test("^\\\\d+\$", "12345"))
        state.set("not_match", regex.test("^\\\\d+\$", "123a"))
        state.set("first", regex.firstMatch("\\\\d+", "abc123def456"))
        
        local all = regex.findAll("\\\\d+", "abc123def456")
        state.set("all_count", #all)
        state.set("all_1", all[1])
        state.set("all_2", all[2])

        state.set("replaced", regex.replace("\\\\d+", "a1b2c", "#"))
        state.set("replaced_all", regex.replaceAll("\\\\d+", "a1b2c", "#"))
      ''');

      expect(delegate.getState('is_match'), true);
      expect(delegate.getState('not_match'), false);
      expect(delegate.getState('first'), '123');
      expect(delegate.getState('all_count'), 2);
      expect(delegate.getState('all_1'), '123');
      expect(delegate.getState('all_2'), '456');
      expect(delegate.getState('replaced'), 'a#b2c');
      expect(delegate.getState('replaced_all'), 'a#b#c');
    });

    test('ColorApi Hex, RGB 与 HSL 颜色空间互相转换', () {
      engine.loadAndExecute('''
        local rgb = color.hexToRgb("#FF8000")
        state.set("rgb_r", rgb.r)
        state.set("rgb_g", rgb.g)
        state.set("rgb_b", rgb.b)

        state.set("hex_str", color.rgbToHex(255, 128, 0))

        local hsl = color.rgbToHsl(255, 0, 0)
        state.set("hsl_h", hsl.h)
        state.set("hsl_s", hsl.s)
        state.set("hsl_l", hsl.l)

        local fromHsl = color.hslToRgb(0, 1.0, 0.5)
        state.set("from_h_r", fromHsl.r)
        state.set("from_h_g", fromHsl.g)
        state.set("from_h_b", fromHsl.b)
      ''');

      expect(delegate.getState('rgb_r'), 255);
      expect(delegate.getState('rgb_g'), 128);
      expect(delegate.getState('rgb_b'), 0);
      expect(delegate.getState('hex_str'), '#FF8000');
      expect(delegate.getState('hsl_h'), 0.0);
      expect(delegate.getState('hsl_s'), 1.0);
      expect(delegate.getState('hsl_l'), 0.5);
      expect(delegate.getState('from_h_r'), 255);
      expect(delegate.getState('from_h_g'), 0);
      expect(delegate.getState('from_h_b'), 0);
    });

    test('UtilApi formatTime 与 parseTime', () {
      engine.loadAndExecute('''
        local ms = 1700000000000
        local formatted = util.formatTime(ms, "yyyy-MM-dd HH:mm:ss")
        state.set("formatted", formatted)
        local parsed = util.parseTime(formatted, "yyyy-MM-dd HH:mm:ss")
        state.set("parsed_ms", parsed)
      ''');

      expect(delegate.getState('formatted'), isA<String>());
      expect(delegate.getState('parsed_ms'), 1700000000000);
    });

    test('NetworkApi 支持 put, delete 与 request 方法绑定', () {
      engine.loadAndExecute('''
        state.set("has_put", type(network.put))
        state.set("has_delete", type(network.delete))
        state.set("has_request", type(network.request))
      ''');

      expect(delegate.getState('has_put'), 'function');
      expect(delegate.getState('has_delete'), 'function');
      expect(delegate.getState('has_request'), 'function');
    });

    test('FsApi 扩展: readHex, writeHex, copy, move 与 fileSize', () {
      final tempDir = Directory.systemTemp.createTempSync('ptx_fs_ext_');
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      final fsCtx = PluginContext(
        pluginId: 'fs_ext_test',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {PluginPermission.storage},
        rootDir: tempDir,
      );
      final fsEngine = LuaEngine(context: fsCtx, delegate: delegate);

      fsEngine.loadAndExecute('''
        -- 写入十六进制数据 (对应 ASCII: "Antigravity")
        -- "416e746967726176697479"
        local ok = fs.writeHex("test_bin.dat", "416e746967726176697479")
        state.set("write_ok", ok)
        state.set("bin_size", fs.fileSize("test_bin.dat"))
        state.set("read_hex", fs.readHex("test_bin.dat"))
        state.set("read_hex_sub", fs.readHex("test_bin.dat", 0, 4))

        -- 测试沙箱内复制与移动
        fs.copy("test_bin.dat", "copy_bin.dat")
        state.set("copy_exists", fs.exists("copy_bin.dat"))

        fs.move("copy_bin.dat", "moved_bin.dat")
        state.set("moved_exists", fs.exists("moved_bin.dat"))
        state.set("old_exists", fs.exists("copy_bin.dat"))
      ''');

      expect(delegate.getState('write_ok'), isTrue);
      expect(delegate.getState('bin_size'), 11);
      expect(delegate.getState('read_hex'), '416e746967726176697479');
      expect(delegate.getState('read_hex_sub'), '416e7469');
      expect(delegate.getState('copy_exists'), isTrue);
      expect(delegate.getState('moved_exists'), isTrue);
      expect(delegate.getState('old_exists'), isFalse);
    });

    test('ArchiveApi: zip, list 与 unzip', () {
      final tempDir = Directory.systemTemp.createTempSync('ptx_archive_');
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      final arcCtx = PluginContext(
        pluginId: 'archive_test',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {PluginPermission.storage},
        rootDir: tempDir,
      );
      final arcEngine = LuaEngine(context: arcCtx, delegate: delegate);

      arcEngine.loadAndExecute('''
        -- 准备测试文件
        fs.writeFile("sub/f1.txt", "hello")
        fs.writeFile("sub/f2.txt", "world")

        -- 压缩目录
        local zipOk = archive.zip("sub", "bundle.zip")
        state.set("zip_ok", zipOk)

        -- 读取条目列表
        local list = archive.list("bundle.zip")
        state.set("list_len", #list)

        -- 解压到新目录
        local unzipOk = archive.unzip("bundle.zip", "unpacked")
        state.set("unzip_ok", unzipOk)
        state.set("f1_content", fs.readFile("unpacked/f1.txt"))
        state.set("f2_content", fs.readFile("unpacked/f2.txt"))
      ''');

      expect(delegate.getState('zip_ok'), isTrue);
      expect(delegate.getState('list_len'), 2);
      expect(delegate.getState('unzip_ok'), isTrue);
      expect(delegate.getState('f1_content'), 'hello');
      expect(delegate.getState('f2_content'), 'world');
    });

    test('DocumentApi: csvParse 与 csvStringify 往返转换', () {
      engine.loadAndExecute('''
        local csv = 'name,score,desc\\nAlice,100,"good, job"\\nBob,90,"said ""hi"""'
        local rows = document.csvParse(csv)
        state.set("row_count", #rows)
        state.set("r1_c1", rows[1][1])
        state.set("r2_c3", rows[2][3])
        state.set("r3_c3", rows[3][3])

        local stringified = document.csvStringify(rows)
        state.set("stringified", stringified)
        local re_rows = document.csvParse(stringified)
        state.set("re_row_count", #re_rows)
        state.set("re_r2_c3", re_rows[2][3])
      ''');

      expect(delegate.getState('row_count'), 3);
      expect(delegate.getState('r1_c1'), 'name');
      expect(delegate.getState('r2_c3'), 'good, job');
      expect(delegate.getState('r3_c3'), 'said "hi"');
      expect(delegate.getState('re_row_count'), 3);
      expect(delegate.getState('re_r2_c3'), 'good, job');
    });

    test('DocumentApi: markdownToHtml 标题、强调与代码块', () {
      engine.loadAndExecute('''
        local md = "# Hello\\n**Bold text** and `inline code`\\n- Item 1\\n- Item 2"
        local html = document.markdownToHtml(md)
        state.set("html", html)
      ''');

      final html = delegate.getState('html') as String;
      expect(html, contains('<h1>Hello</h1>'));
      expect(html, contains('<strong>Bold text</strong>'));
      expect(html, contains('<code>inline code</code>'));
      expect(html, contains('<li>Item 1</li>'));
      expect(html, contains('<li>Item 2</li>'));
    });

    test('TorchApi: 权限控制与开关状态', () {
      // 未声明权限报错
      expect(
        () => engine.loadAndExecute('torch.on()'),
        throwsA(isA<Exception>()),
      );

      // 声明权限后测试
      final torchCtx = PluginContext(
        pluginId: 'torch_test',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {PluginPermission.torch},
      );
      final torchEngine = LuaEngine(context: torchCtx, delegate: delegate);

      torchEngine.loadAndExecute('''
        state.set("init_torch", torch.isOn())
        torch.on()
      ''');
      expect(delegate.getState('init_torch'), isFalse);
      expect(delegate.torchState, isTrue);

      torchEngine.loadAndExecute('''
        torch.off()
      ''');
      expect(delegate.torchState, isFalse);
    });

    test('QrcodeApi: 生成二维码矩阵与尺寸', () {
      engine.loadAndExecute('''
        local res = qrcode.matrix("https://github.com")
        state.set("qr_cols", res.cols)
        state.set("qr_rows", res.rows)
        state.set("qr_len", string.len(res.data))
      ''');

      final cols = delegate.getState('qr_cols') as int;
      final rows = delegate.getState('qr_rows') as int;
      final len = delegate.getState('qr_len') as int;

      expect(cols, greaterThan(0));
      expect(rows, cols);
      expect(len, cols * rows);
    });
  });
}
