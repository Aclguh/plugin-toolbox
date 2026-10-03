import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_toolbox_dui/plugin_toolbox_dui.dart';

class MockActionExecutor implements DuiActionExecutor {
  final List<String> calledFunctions = [];
  final List<String> toasts = [];

  @override
  void callLua(String functionName, [List<dynamic> args = const []]) {
    calledFunctions.add(functionName);
  }

  @override
  void showToast(String message) {
    toasts.add(message);
  }
}

void main() {
  group('DuiState Tests', () {
    test('interpolates state variables in template strings', () {
      final state = DuiState();
      state.set('name', 'Plugin');
      state.set('count', 42);

      expect(state.interpolate('Hello {{state.name}}!'), 'Hello Plugin!');
      expect(state.interpolate('Items: {{state.count}}'), 'Items: 42');
      expect(state.interpolate('Unknown: {{state.unknown}}'), 'Unknown: ');
    });

    test('evaluates visible expression correctly', () {
      final state = DuiState();
      expect(state.evaluateVisible(null), isTrue);
      expect(state.evaluateVisible(true), isTrue);
      expect(state.evaluateVisible(false), isFalse);
      expect(state.evaluateVisible('true'), isTrue);
      expect(state.evaluateVisible('false'), isFalse);

      state.set('hasError', false);
      expect(state.evaluateVisible('{{state.hasError}}'), isFalse);

      state.set('hasError', true);
      expect(state.evaluateVisible('{{state.hasError}}'), isTrue);
    });
  });

  group('DuiUtils 颜色解析', () {
    test('parseColor 支持 #RRGGBB / #AARRGGBB / 无 # 前缀', () {
      expect(DuiUtils.parseColor('#788CFF'), const Color(0xFF788CFF));
      expect(DuiUtils.parseColor('788CFF'), const Color(0xFF788CFF));
      expect(DuiUtils.parseColor('#80112233'), const Color(0x80112233));
    });

    test('parseColor 非法输入安全返回 null 而非抛异常', () {
      expect(DuiUtils.parseColor(null), isNull);
      expect(DuiUtils.parseColor(''), isNull);
      expect(DuiUtils.parseColor('#12345'), isNull);
      expect(DuiUtils.parseColor('#GGHHII'), isNull);
      expect(DuiUtils.parseColor('0x788CFF'), isNull);
      expect(DuiUtils.parseColor('#-123456'), isNull);
    });
  });

  group('DuiRenderer Tests', () {
    testWidgets('renders Text, Button and handles click events', (tester) async {
      final state = DuiState();
      final executor = MockActionExecutor();
      final handler = DuiEventHandler(state: state, executor: executor);
      final renderer = DuiRenderer(state: state, eventHandler: handler);

      state.set('result', 'Initial Text');

      final node = {
        'type': 'Column',
        'children': [
          {
            'type': 'Text',
            'props': {'text': 'Value: {{state.result}}'},
          },
          {
            'type': 'FilledButton',
            'props': {'text': 'Click Me'},
            'events': {
              'onPressed': {'action': 'callLua', 'function': 'onButtonClicked'}
            }
          }
        ]
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => renderer.buildWidget(context, node),
            ),
          ),
        ),
      );

      expect(find.text('Value: Initial Text'), findsOneWidget);
      expect(find.text('Click Me'), findsOneWidget);

      await tester.tap(find.text('Click Me'));
      expect(executor.calledFunctions, contains('onButtonClicked'));
    });
  });

  group('DuiRenderer 响应式与容错', () {
    Widget buildHost(DuiRenderer renderer, Map<String, dynamic> node) {
      return MaterialApp(
        home: Scaffold(
          body: Builder(builder: (context) => renderer.build(context, node)),
        ),
      );
    }

    testWidgets('状态变更经 ListenableBuilder 自动刷新 UI', (tester) async {
      final state = DuiState();
      final handler = DuiEventHandler(state: state, executor: MockActionExecutor());
      final renderer = DuiRenderer(state: state, eventHandler: handler);

      final node = {
        'type': 'Text',
        'props': {'text': 'Value: {{state.result}}'},
      };

      await tester.pumpWidget(buildHost(renderer, node));
      expect(find.text('Value: Initial'), findsNothing);

      state.set('result', 'Initial');
      await tester.pump();
      expect(find.text('Value: Initial'), findsOneWidget);

      // 无需任何外部 setState, 状态写入后 UI 自动更新
      state.set('result', 'Updated');
      await tester.pump();
      expect(find.text('Value: Updated'), findsOneWidget);
    });

    testWidgets('registerFactory 支持扩展自定义组件类型', (tester) async {
      final state = DuiState();
      final handler = DuiEventHandler(state: state, executor: MockActionExecutor());
      final renderer = DuiRenderer(state: state, eventHandler: handler);
      renderer.registerFactory(
        'Badge',
        (node) => Text('BADGE:${node.props['label']}',
            textDirection: TextDirection.ltr),
      );

      final node = {
        'type': 'Badge',
        'props': {'label': 'X'},
      };

      await tester.pumpWidget(buildHost(renderer, node));
      expect(find.text('BADGE:X'), findsOneWidget);
    });

    testWidgets('未知组件类型安全降级为空白而非崩溃', (tester) async {
      final state = DuiState();
      final handler = DuiEventHandler(state: state, executor: MockActionExecutor());
      final renderer = DuiRenderer(state: state, eventHandler: handler);

      await tester.pumpWidget(buildHost(renderer, {
        'type': 'DefinitelyUnknownWidget',
        'props': {},
      }));

      expect(tester.takeException(), isNull);
    });

    testWidgets('数值属性为字符串时安全解析不崩溃 (类型容错)', (tester) async {
      final state = DuiState();
      final handler = DuiEventHandler(state: state, executor: MockActionExecutor());
      final renderer = DuiRenderer(state: state, eventHandler: handler);

      final node = {
        'type': 'SizedBox',
        'props': {'width': '100', 'height': '50', 'maxLines': '3'},
      };

      await tester.pumpWidget(buildHost(renderer, node));
      expect(tester.takeException(), isNull);

      final sizedBox = tester.widget<SizedBox>(
        find.byWidgetPredicate((w) => w is SizedBox && w.width == 100.0),
      );
      expect(sizedBox.height, 50.0);
    });

    testWidgets('Image src 路径穿越被拦截, 不发起任何文件加载', (tester) async {
      final state = DuiState();
      final handler = DuiEventHandler(state: state, executor: MockActionExecutor());
      final renderer = DuiRenderer(
        state: state,
        eventHandler: handler,
        pluginRootDir: Directory.systemTemp,
      );

      final node = {
        'type': 'Image',
        'props': {'src': '../../../../etc/passwd'},
      };

      await tester.pumpWidget(buildHost(renderer, node));
      expect(tester.takeException(), isNull);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('Image src 指向沙箱内合法相对路径时正常构建', (tester) async {
      final state = DuiState();
      final handler = DuiEventHandler(state: state, executor: MockActionExecutor());
      final renderer = DuiRenderer(
        state: state,
        eventHandler: handler,
        pluginRootDir: Directory.systemTemp,
      );

      final node = {
        'type': 'Image',
        'props': {'src': 'definitely_missing_icon.png'},
      };

      await tester.pumpWidget(buildHost(renderer, node));
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('Container color 属性渲染背景色, 非法值降级为无色不崩溃', (tester) async {
      final state = DuiState();
      final handler = DuiEventHandler(state: state, executor: MockActionExecutor());
      final renderer = DuiRenderer(state: state, eventHandler: handler);

      final node = {
        'type': 'Column',
        'children': [
          {
            'type': 'Container',
            'props': {'color': '#788CFF', 'width': 48, 'height': 24},
          },
          {
            'type': 'Container',
            'props': {'color': 'not-a-color', 'width': 48, 'height': 24},
          },
        ]
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => renderer.buildWidget(context, node),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);

      final containers =
          tester.widgetList<Container>(find.byType(Container)).toList();
      expect((containers[0].decoration as BoxDecoration).color,
          const Color(0xFF788CFF));
      expect((containers[1].decoration as BoxDecoration).color, isNull);
    });

    testWidgets('TextField 双向绑定: 输入回写状态, 状态变更同步 UI', (tester) async {
      final state = DuiState();
      final handler = DuiEventHandler(state: state, executor: MockActionExecutor());
      final renderer = DuiRenderer(state: state, eventHandler: handler);

      final node = {
        'type': 'TextField',
        'ref': 'input',
        'props': {},
      };

      await tester.pumpWidget(buildHost(renderer, node));

      // 用户输入 -> 状态回写
      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pump();
      expect(state.get('input'), 'hello');

      // 宿主写入状态 -> UI 更新
      state.set('input', 'from host');
      await tester.pump();
      expect(find.text('from host'), findsOneWidget);
    });
  });
}
