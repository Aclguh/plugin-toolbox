import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_toolbox_dui/plugin_toolbox_dui.dart';

class _MockExecutor implements DuiActionExecutor {
  final List<String> calledFunctions = [];
  final List<List<dynamic>> calledArgs = [];
  final List<String> toasts = [];

  @override
  void callLua(String functionName, [List<dynamic> args = const []]) {
    calledFunctions.add(functionName);
    calledArgs.add(args);
  }

  @override
  void showToast(String message) {
    toasts.add(message);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DuiEventHandler Tests (P3-2)', () {
    late DuiState state;
    late _MockExecutor executor;
    late DuiEventHandler handler;

    setUp(() {
      state = DuiState();
      executor = _MockExecutor();
      handler = DuiEventHandler(state: state, executor: executor);
    });

    test('callLua 正常派发函数名与参数', () {
      final event = {
        'action': 'callLua',
        'function': 'onCalculate',
        'args': [1, 'arg2', true],
      };

      handler.handleEvent(event);
      expect(executor.calledFunctions, ['onCalculate']);
      expect(executor.calledArgs.first, [1, 'arg2', true]);
    });

    test('callLua 缺省 args 时默认为空参数列表', () {
      final event = {
        'action': 'callLua',
        'function': 'doRefresh',
      };

      handler.handleEvent(event);
      expect(executor.calledFunctions, ['doRefresh']);
      expect(executor.calledArgs.first, isEmpty);
    });

    test('callLua 缺少 function 时安全跳过', () {
      final event = {
        'action': 'callLua',
      };

      handler.handleEvent(event);
      expect(executor.calledFunctions, isEmpty);
    });

    test('setState 正确更新 DuiState 对应键值', () {
      final event = {
        'action': 'setState',
        'key': 'currentResult',
      };

      handler.handleEvent(event, 'new_value_42');
      expect(state.get('currentResult'), 'new_value_42');
    });

    test('setState 缺少 key 时安全忽略', () {
      final event = {
        'action': 'setState',
      };

      handler.handleEvent(event, 'value');
      expect(state.getAll(), isEmpty);
    });

    test('copyToClipboard 复制插值后的文本并显示 Toast', () async {
      String? copiedText;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedText = (call.arguments as Map)['text'] as String?;
          return null;
        }
        return null;
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding.instance
          .defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));

      state.set('code', 'ABC-123');

      final event = {
        'action': 'copyToClipboard',
        'text': 'Code is: {{state.code}}',
      };

      handler.handleEvent(event);

      expect(copiedText, 'Code is: ABC-123');
      expect(executor.toasts, ['已复制到剪贴板']);
    });

    test('copyToClipboard 未声明权限时阻断复制并提示权限不足', () async {
      String? copiedText;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedText = (call.arguments as Map)['text'] as String?;
          return null;
        }
        return null;
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding.instance
          .defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));

      final restrictedHandler = DuiEventHandler(
        state: state,
        executor: executor,
        permissionChecker: (perm) => false, // 拒绝所有权限
      );

      final event = {
        'action': 'copyToClipboard',
        'text': 'Secret Data',
      };

      restrictedHandler.handleEvent(event);

      expect(copiedText, isNull);
      expect(executor.toasts, contains(predicate<String>((s) => s.contains('权限不足'))));
    });

    test('容错降级：null 或非法事件定义安全无害忽略', () {
      expect(() => handler.handleEvent(null), returnsNormally);
      expect(() => handler.handleEvent({}), returnsNormally);
      expect(() => handler.handleEvent({'action': 'unknownAction'}), returnsNormally);
      expect(() => handler.handleEvent({'unknown_key': 123}), returnsNormally);
      // dynamic map 容错
      final dynamicMap = <dynamic, dynamic>{
        'action': 'callLua',
        'function': 'testDynamic',
      };
      expect(() => handler.handleEvent(dynamicMap), returnsNormally);
      expect(executor.calledFunctions, contains('testDynamic'));
    });
  });
}
