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

    testWidgets('PixelGrid 按状态位图渲染像素方块尺寸, 数据异常安全降级', (tester) async {
      final state = DuiState();
      final handler = DuiEventHandler(state: state, executor: MockActionExecutor());
      final renderer = DuiRenderer(state: state, eventHandler: handler);

      Widget buildHost(Map<String, dynamic> node) => MaterialApp(
            home: Scaffold(
              body: Builder(builder: (context) => renderer.build(context, node)),
            ),
          );

      // 3x3 位图, 单格 10 逻辑像素 -> 30x30
      state.set('px', '010111101');
      await tester.pumpWidget(buildHost({
        'type': 'PixelGrid',
        'props': {'data': '{{state.px}}', 'cols': '3', 'cellSize': '10'},
      }));

      final matches = tester.widgetList<SizedBox>(find.byWidgetPredicate(
        (w) => w is SizedBox && w.width == 30.0,
      ));
      expect(matches, isNotEmpty);
      expect(matches.first.height, 30.0);
      final pixelPaint = tester.widgetList<CustomPaint>(find.byType(CustomPaint)).where(
        (p) => p.painter.runtimeType.toString().endsWith('_PixelGridPainter'),
      );
      expect(pixelPaint, isNotEmpty);

      // 位图长度与列数不匹配 -> 空白降级
      state.set('px', '0101');
      await tester.pumpWidget(buildHost({
        'type': 'PixelGrid',
        'props': {'data': '{{state.px}}', 'cols': '3', 'cellSize': '10'},
      }));
      expect(
        tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .where((p) =>
                p.painter.runtimeType.toString().endsWith('_PixelGridPainter')),
        isEmpty,
      );

      // 空数据 -> 空白降级
      await tester.pumpWidget(buildHost({
        'type': 'PixelGrid',
        'props': {'data': '{{state.empty}}', 'cols': '3', 'cellSize': '10'},
      }));
      expect(
        tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .where((p) =>
                p.painter.runtimeType.toString().endsWith('_PixelGridPainter')),
        isEmpty,
      );
    });

    testWidgets('Container color 支持状态插值, 非法值降级为无色', (tester) async {
      final state = DuiState();
      final handler = DuiEventHandler(state: state, executor: MockActionExecutor());
      final renderer = DuiRenderer(state: state, eventHandler: handler);

      Widget buildHost(Map<String, dynamic> node) => MaterialApp(
            home: Scaffold(
              body: Builder(builder: (context) => renderer.build(context, node)),
            ),
          );

      state.set('swatch', '#26366A');
      await tester.pumpWidget(buildHost({
        'type': 'Container',
        'props': {'color': '{{state.swatch}}', 'width': 40, 'height': 20},
      }));

      var container = tester.widget<Container>(find.byType(Container));
      expect((container.decoration as BoxDecoration).color,
          const Color(0xFF26366A));

      // 状态变更后插值随之更新
      state.set('swatch', '#FF0000');
      await tester.pump();
      container = tester.widget<Container>(find.byType(Container));
      expect((container.decoration as BoxDecoration).color,
          const Color(0xFFFF0000));

      // 非法插值结果安全降级
      state.set('swatch', 'not-a-color');
      await tester.pump();
      container = tester.widget<Container>(find.byType(Container));
      expect((container.decoration as BoxDecoration).color, isNull);
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

    testWidgets('TextField didUpdateWidget 保留合理光标位置 (P3-5)', (tester) async {
      final state = DuiState();
      final handler = DuiEventHandler(state: state, executor: MockActionExecutor());
      final renderer = DuiRenderer(state: state, eventHandler: handler);

      final node = {
        'type': 'TextField',
        'ref': 'text_ref',
        'props': {},
      };

      await tester.pumpWidget(buildHost(renderer, node));
      await tester.enterText(find.byType(TextField), '12345');
      await tester.pump();

      // 模拟光标设置在位置 3
      final textFieldFinder = find.byType(TextField);
      final editableText = tester.widget<EditableText>(
        find.descendant(of: textFieldFinder, matching: find.byType(EditableText)),
      );
      editableText.controller.selection = const TextSelection.collapsed(offset: 3);

      // 外部更新文本为较长字符串，光标应维持在 3
      state.set('text_ref', '12345678');
      await tester.pump();
      expect(editableText.controller.selection.baseOffset, 3);

      // 外部更新文本为较短字符串，光标应被 clamp 到短字符串长度
      state.set('text_ref', '12');
      await tester.pump();
      expect(editableText.controller.selection.baseOffset, 2);
    });

    test('DuiState extractKeys 与 key-level 局部通知 (P2-1)', () {
      final state = DuiState();
      expect(DuiState.extractKeys('Hello {{state.user}}, count: {{state.count}}'),
          equals({'user', 'count'}));
      expect(DuiState.extractKeys('plain text'), isEmpty);
      expect(DuiState.extractKeys(null), isEmpty);

      int userNotified = 0;
      int countNotified = 0;
      state.listenableForKey('user').addListener(() => userNotified++);
      state.listenableForKey('count').addListener(() => countNotified++);

      state.set('user', 'Alice');
      expect(userNotified, 1);
      expect(countNotified, 0);

      state.set('count', 10);
      expect(userNotified, 1);
      expect(countNotified, 1);

      // 相同值不触发通知
      state.set('count', 10);
      expect(countNotified, 1);
    });

    testWidgets('DuiRenderer 渲染 Switch、Slider、Dropdown、ProgressBar、Divider 与 Wrap 组件及双向绑定', (tester) async {
      final state = DuiState();
      final executor = MockActionExecutor();
      final handler = DuiEventHandler(state: state, executor: executor);
      final renderer = DuiRenderer(state: state, eventHandler: handler);

      state.set('switch_val', false);
      state.set('slider_val', 0.5);
      state.set('select_val', 'B');
      state.set('progress_val', 0.75);

      final node = {
        'type': 'Column',
        'children': [
          {
            'type': 'Switch',
            'ref': 'switch_val',
            'props': {'label': '开启功能'},
          },
          {
            'type': 'Slider',
            'ref': 'slider_val',
            'props': {'min': 0.0, 'max': 1.0},
          },
          {
            'type': 'Dropdown',
            'ref': 'select_val',
            'props': {
              'items': ['A', 'B', 'C'],
              'hint': '请选择',
            },
          },
          {
            'type': 'ProgressBar',
            'props': {'value': '{{state.progress_val}}'},
          },
          {
            'type': 'Divider',
            'props': {'height': 16.0, 'thickness': 2.0},
          },
          {
            'type': 'Wrap',
            'props': {'spacing': 8.0},
            'children': [
              {
                'type': 'Text',
                'props': {'text': 'Tag1'},
              },
              {
                'type': 'Text',
                'props': {'text': 'Tag2'},
              },
            ],
          },
        ],
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

      expect(find.byType(Switch), findsOneWidget);
      expect(find.byType(Slider), findsOneWidget);
      expect(find.byType(DropdownButton<String>), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.byType(Divider), findsOneWidget);
      expect(find.byType(Wrap), findsOneWidget);
      expect(find.text('开启功能'), findsOneWidget);
      expect(find.text('Tag1'), findsOneWidget);

      // 点击 Switch 触发状态回写
      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(state.get('switch_val'), isTrue);
    });

    testWidgets('DuiRenderer 渲染 Tabs 分段标签页并响应切换', (tester) async {
      final state = DuiState();
      final executor = MockActionExecutor();
      final handler = DuiEventHandler(state: state, executor: executor);
      final renderer = DuiRenderer(state: state, eventHandler: handler);

      state.set('tab_idx', 0);

      final node = {
        'type': 'Tabs',
        'ref': 'tab_idx',
        'props': {
          'tabs': ['第一页', '第二页'],
          'initialIndex': 0,
        },
        'children': [
          {
            'type': 'Text',
            'props': {'text': '内容一'},
          },
          {
            'type': 'Text',
            'props': {'text': '内容二'},
          },
        ],
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

      expect(find.text('第一页'), findsOneWidget);
      expect(find.text('第二页'), findsOneWidget);
      expect(find.text('内容一'), findsOneWidget);
      expect(find.text('内容二'), findsNothing);

      // 切换至第二页
      await tester.tap(find.text('第二页'));
      await tester.pump();

      expect(state.get('tab_idx'), 1);
      expect(find.text('内容一'), findsNothing);
      expect(find.text('内容二'), findsOneWidget);
    });

    testWidgets('DuiRenderer 渲染 MarkdownView 与状态插值', (tester) async {
      final state = DuiState();
      final executor = MockActionExecutor();
      final handler = DuiEventHandler(state: state, executor: executor);
      final renderer = DuiRenderer(state: state, eventHandler: handler);

      state.set('md_text', '# 标题一\n> 引用说明\n- 列表项\n```dart\nvoid main() {}\n```');

      final node = {
        'type': 'MarkdownView',
        'props': {
          'text': '{{state.md_text}}',
        },
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

      expect(find.byType(DuiMarkdownView), findsOneWidget);
      expect(find.text('标题一'), findsOneWidget);
      expect(find.text('引用说明'), findsOneWidget);
      expect(find.text('void main() {}'), findsOneWidget);
    });
  });
}
