import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';
import 'package:plugin_toolbox_lua/plugin_toolbox_lua.dart';

import 'helpers/lua_test_helpers.dart';

Future<void> _waitFor(
  bool Function() condition, {
  int maxTries = 40,
  int stepMs = 25,
}) =>
    waitForCondition(condition, maxTries: maxTries, stepMs: stepMs);

void main() {
  group('CodecApi 编解码工具进阶特性测试', () {
    late PluginContext context;
    late MockLuaHostDelegate delegate;
    late LuaEngine engine;

    setUp(() {
      delegate = MockLuaHostDelegate();
      context = PluginContext(
        pluginId: 'codec_test',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: const {},
      );
      engine = LuaEngine(context: context, delegate: delegate);
    });

    tearDown(() => engine.close());

    test('codec.hexDump 格式化输出十六进制转储', () {
      engine.loadAndExecute('''
        local dump = codec.hexDump("Hello World! 1234")
        state.set("has_offset", dump:find("00000000") ~= nil)
        state.set("has_pipe", dump:find("|Hello World! 1234|") ~= nil)
      ''');

      expect(delegate.getState('has_offset'), isTrue);
      expect(delegate.getState('has_pipe'), isTrue);
    });

    test('codec.htmlEntitiesEncode 与 htmlEntitiesDecode 实体转义与反转义', () {
      engine.loadAndExecute(r'''
        local raw = '<div class="test">Fish & Chips "OK"</div>'
        local encoded = codec.htmlEntitiesEncode(raw)
        state.set("encoded_html", encoded)
        local decoded = codec.htmlEntitiesDecode(encoded)
        state.set("decoded_html", decoded)

        -- 测试数字实体与十六进制实体解码 &#65; (A), &#x42; (B)
        local customDecoded = codec.htmlEntitiesDecode("&#65;&#x42;&nbsp;")
        state.set("custom_decoded", customDecoded)
      ''');

      expect(delegate.getState('encoded_html'), contains('&lt;div'));
      expect(delegate.getState('encoded_html'), contains('&amp;'));
      expect(delegate.getState('decoded_html'),
          '<div class="test">Fish & Chips "OK"</div>');
      expect(delegate.getState('custom_decoded'), 'AB ');
    });

    test('codec.punycodeEncode 与 punycodeDecode 国际化域名转换', () {
      engine.loadAndExecute('''
        local ascii = codec.punycodeEncode("中文.com")
        state.set("puny_ascii", ascii)
        local unicode = codec.punycodeDecode(ascii)
        state.set("puny_unicode", unicode)
      ''');

      expect(delegate.getState('puny_ascii'), 'xn--fiq228c.com');
      expect(delegate.getState('puny_unicode'), '中文.com');
    });

    test('codec.jwtDecode 非法结构异常降级', () {
      engine.loadAndExecute('''
        local res, err = codec.jwtDecode("invalid_token_without_dots")
        state.set("jwt_nil", res == nil)
        state.set("jwt_err", err)
      ''');

      expect(delegate.getState('jwt_nil'), isTrue);
      expect(delegate.getState('jwt_err'), contains('非法 JWT'));
    });
  });

  group('TaskApi 后台 Worker 调度扩展参数测试', () {
    late PluginContext context;
    late MockLuaHostDelegate delegate;
    late LuaEngine engine;

    setUp(() {
      delegate = MockLuaHostDelegate();
      context = PluginContext(
        pluginId: 'task_ext_test',
        storage: InMemoryPluginStorage(),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: const {},
      );
      engine = LuaEngine(context: context, delegate: delegate);
    });

    tearDown(() => engine.close());

    test('task.run 支持配置选项表 timeoutMs 与 budget', () async {
      engine.loadAndExecute('''
        task.run("function main(args) return args.x * 2 end", { x = 21 }, { timeoutMs = 2000, budget = 500000 }, function(res)
          state.set("task_res_ok", res.ok)
          state.set("task_res_val", res.result)
        end)
      ''');

      await _waitFor(() => delegate.getState('task_res_ok') != null);
      expect(delegate.getState('task_res_ok'), isTrue);
      expect(delegate.getState('task_res_val'), 42);
    });
  });
}
