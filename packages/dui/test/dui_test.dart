import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_toolbox_dui/plugin_toolbox_dui.dart';

class MockActionExecutor implements DuiActionExecutor {
  final List<String> calledFunctions = [];
  final Map<String, List<dynamic>> callArgs = {};
  final List<String> toasts = [];

  @override
  void callLua(String functionName, [List<dynamic> args = const []]) {
    calledFunctions.add(functionName);
    callArgs[functionName] = args;
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

    test('evaluates negated visible expression with !', () {
      final state = DuiState();
      state.set('loading', true);
      expect(state.evaluateVisible('!{{state.loading}}'), isFalse);

      state.set('loading', false);
      expect(state.evaluateVisible('!{{state.loading}}'), isTrue);

      state.set('text', 'content');
      expect(state.evaluateVisible('!{{state.text}}'), isFalse);
      state.set('text', '');
      expect(state.evaluateVisible('!{{state.text}}'), isTrue);

      state.set('count', 5);
      expect(state.evaluateVisible('!{{state.count}}'), isFalse);
      state.set('count', 0);
      expect(state.evaluateVisible('!{{state.count}}'), isTrue);
    });

    test(
        'evaluates composite visible expressions with comparison and logical operators',
        () {
      final state = DuiState();
      state.set('count', 10);
      state.set('isReady', true);
      state.set('status', 'active');

      // 逻辑与和大小比较
      expect(state.evaluateVisible('{{state.count > 0 && state.isReady}}'),
          isTrue);
      state.set('isReady', false);
      expect(state.evaluateVisible('{{state.count > 0 && state.isReady}}'),
          isFalse);

      // 逻辑或
      state.set('isVip', true);
      expect(state.evaluateVisible('{{state.isReady || state.isVip}}'), isTrue);

      // 等值与不等值比较
      expect(state.evaluateVisible("{{state.status}} == 'active'"), isTrue);
      expect(state.evaluateVisible("{{state.status}} != 'active'"), isFalse);

      // extractKeys 提取复合表达式中的键
      final keys = DuiState.extractKeys(
          'state.count > 0 && state.isReady || {{state.isVip}}');
      expect(keys, containsAll(['count', 'isReady', 'isVip']));
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

  group('DuiUtils 图标解析与回退', () {
    test('parseIcon 支持精确匹配常用 Material 图标', () {
      expect(DuiUtils.parseIcon('lock'), Icons.lock);
      expect(DuiUtils.parseIcon('timer'), Icons.timer);
      expect(DuiUtils.parseIcon('palette'), Icons.palette);
      expect(DuiUtils.parseIcon('translate'), Icons.translate);
      expect(DuiUtils.parseIcon('calculate'), Icons.calculate);
      expect(DuiUtils.parseIcon('wifi'), Icons.wifi);
      expect(DuiUtils.parseIcon('bluetooth'), Icons.bluetooth);
    });

    test('parseIcon 对未完全匹配的图标名称提供语义智能降级', () {
      expect(DuiUtils.parseIcon('user_lock_key'), Icons.lock);
      expect(DuiUtils.parseIcon('custom_timer_stopwatch'), Icons.timer);
      expect(DuiUtils.parseIcon('custom_schedule_clock'), Icons.access_time);
      expect(DuiUtils.parseIcon('my_calculator_app'), Icons.calculate);
      expect(DuiUtils.parseIcon('unknown_foobar_xyz'), Icons.extension);
      expect(DuiUtils.parseIcon(null), Icons.extension);
      expect(DuiUtils.parseIcon(''), Icons.extension);
    });
  });

  group('DuiRenderer Tests', () {
    testWidgets('renders Text, Button and handles click events',
        (tester) async {
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

    testWidgets('renders generic Button as filled and outlined',
        (tester) async {
      final state = DuiState();
      final executor = MockActionExecutor();
      final handler = DuiEventHandler(state: state, executor: executor);
      final renderer = DuiRenderer(state: state, eventHandler: handler);

      final node = {
        'type': 'Column',
        'children': [
          {
            'type': 'Button',
            'props': {'text': 'Default Button'},
            'events': {
              'onPressed': {'action': 'callLua', 'function': 'defaultClicked'}
            }
          },
          {
            'type': 'Button',
            'props': {'text': 'Outlined Button', 'type': 'outlined'},
            'events': {
              'onPressed': {'action': 'callLua', 'function': 'outlinedClicked'}
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

      expect(find.text('Default Button'), findsOneWidget);
      expect(find.text('Outlined Button'), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.byType(OutlinedButton), findsOneWidget);

      await tester.tap(find.text('Default Button'));
      expect(executor.calledFunctions, contains('defaultClicked'));
      await tester.tap(find.text('Outlined Button'));
      expect(executor.calledFunctions, contains('outlinedClicked'));
    });

    testWidgets('DuiScopeContext 支持作用域深层字段解析、可见性计算与事件参数传递', (tester) async {
      final state = DuiState();
      final executor = MockActionExecutor();
      final handler = DuiEventHandler(state: state, executor: executor);
      final renderer = DuiRenderer(state: state, eventHandler: handler);

      const scope = DuiScopeContext(
        item: {
          'id': 'item-101',
          'profile': {'name': 'Alice'},
          'roles': ['admin', 'viewer'],
          'enabled': true,
        },
        index: 2,
      );

      // 1. 作用域解析测试
      expect(scope.resolve(r'$index'), 2);
      expect(scope.resolve(r'$item.id'), 'item-101');
      expect(scope.resolve(r'$item.profile.name'), 'Alice');
      expect(scope.resolve(r'$item.roles.0'), 'admin');
      expect(scope.resolve(r'$item.roles.1'), 'viewer');

      // 2. 模板插值与可见性
      expect(
        state.interpolate(
            r'Index: {{$index}}, User: {{$item.profile.name}}, Role: {{$item.roles.0}}',
            scope),
        'Index: 2, User: Alice, Role: admin',
      );
      expect(state.evaluateVisible(r'$item.enabled == true', scope), isTrue);

      // 3. UI 渲染与作用域事件派发
      final node = {
        'type': 'Column',
        'children': [
          {
            'type': 'Text',
            'props': {
              'text': r'Hello {{$item.profile.name}}',
            },
          },
          {
            'type': 'FilledButton',
            'props': {'text': r'Action {{$index}}'},
            'events': {
              'onPressed': {
                'action': 'callLua',
                'function': 'onItemAction',
                'args': [r'{{$item.id}}', r'{{$index}}'],
              }
            }
          }
        ]
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) =>
                  renderer.buildWidget(context, node, scope: scope),
            ),
          ),
        ),
      );

      expect(find.text('Hello Alice'), findsOneWidget);
      expect(find.text('Action 2'), findsOneWidget);

      await tester.tap(find.text('Action 2'));
      expect(executor.calledFunctions, contains('onItemAction'));
      expect(executor.callArgs['onItemAction'], ['item-101', '2']);
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
      final handler =
          DuiEventHandler(state: state, executor: MockActionExecutor());
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
      final handler =
          DuiEventHandler(state: state, executor: MockActionExecutor());
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
      final handler =
          DuiEventHandler(state: state, executor: MockActionExecutor());
      final renderer = DuiRenderer(state: state, eventHandler: handler);

      await tester.pumpWidget(buildHost(renderer, {
        'type': 'DefinitelyUnknownWidget',
        'props': {},
      }));

      expect(tester.takeException(), isNull);
    });

    testWidgets('数值属性为字符串时安全解析不崩溃 (类型容错)', (tester) async {
      final state = DuiState();
      final handler =
          DuiEventHandler(state: state, executor: MockActionExecutor());
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
      final handler =
          DuiEventHandler(state: state, executor: MockActionExecutor());
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
      final handler =
          DuiEventHandler(state: state, executor: MockActionExecutor());
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

    testWidgets('Image src 支持响应式状态插值, 状态变更触发更新与沙箱拦截', (tester) async {
      final state = DuiState();
      final handler =
          DuiEventHandler(state: state, executor: MockActionExecutor());
      final renderer = DuiRenderer(
        state: state,
        eventHandler: handler,
        pluginRootDir: Directory.systemTemp,
      );

      final node = {
        'type': 'Image',
        'props': {'src': '{{state.imagePath}}'},
      };

      // 1. 初始状态为空，插值后为空字符串，被安全校验拦截不渲染 Image
      await tester.pumpWidget(buildHost(renderer, node));
      expect(find.byType(Image), findsNothing);

      // 2. 更新为合法相对路径，响应式重新构建并显示 Image
      state.set('imagePath', 'test_avatar.png');
      await tester.pump();
      expect(find.byType(Image), findsOneWidget);

      // 3. 更新为越权穿越路径，重新拦截并不渲染 Image
      state.set('imagePath', '../../sensitive.txt');
      await tester.pump();
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('Container color 属性渲染背景色, 非法值降级为无色不崩溃', (tester) async {
      final state = DuiState();
      final handler =
          DuiEventHandler(state: state, executor: MockActionExecutor());
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
      final handler =
          DuiEventHandler(state: state, executor: MockActionExecutor());
      final renderer = DuiRenderer(state: state, eventHandler: handler);

      Widget buildHost(Map<String, dynamic> node) => MaterialApp(
            home: Scaffold(
              body:
                  Builder(builder: (context) => renderer.build(context, node)),
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
      final pixelPaint = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .where(
            (p) =>
                p.painter.runtimeType.toString().endsWith('_PixelGridPainter'),
          );
      expect(pixelPaint, isNotEmpty);

      // 位图长度与列数不匹配 -> 空白降级
      state.set('px', '0101');
      await tester.pumpWidget(buildHost({
        'type': 'PixelGrid',
        'props': {'data': '{{state.px}}', 'cols': '3', 'cellSize': '10'},
      }));
      expect(
        tester.widgetList<CustomPaint>(find.byType(CustomPaint)).where((p) =>
            p.painter.runtimeType.toString().endsWith('_PixelGridPainter')),
        isEmpty,
      );

      // 空数据 -> 空白降级
      await tester.pumpWidget(buildHost({
        'type': 'PixelGrid',
        'props': {'data': '{{state.empty}}', 'cols': '3', 'cellSize': '10'},
      }));
      expect(
        tester.widgetList<CustomPaint>(find.byType(CustomPaint)).where((p) =>
            p.painter.runtimeType.toString().endsWith('_PixelGridPainter')),
        isEmpty,
      );
    });

    testWidgets('Container color 支持状态插值, 非法值降级为无色', (tester) async {
      final state = DuiState();
      final handler =
          DuiEventHandler(state: state, executor: MockActionExecutor());
      final renderer = DuiRenderer(state: state, eventHandler: handler);

      Widget buildHost(Map<String, dynamic> node) => MaterialApp(
            home: Scaffold(
              body:
                  Builder(builder: (context) => renderer.build(context, node)),
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
      final handler =
          DuiEventHandler(state: state, executor: MockActionExecutor());
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

    testWidgets('TextField 支持 debounceMs 输入防抖延时同步', (tester) async {
      final state = DuiState();
      final handler =
          DuiEventHandler(state: state, executor: MockActionExecutor());
      final renderer = DuiRenderer(state: state, eventHandler: handler);

      final node = {
        'type': 'TextField',
        'ref': 'debounced_input',
        'props': {
          'debounceMs': 100,
        },
      };

      await tester.pumpWidget(buildHost(renderer, node));

      // 用户输入
      await tester.enterText(find.byType(TextField), 'fast typing');
      await tester.pump();
      // 防抖期间，状态尚未被写入
      expect(state.get('debounced_input'), isNull);

      // 时间步进 100ms
      await tester.pump(const Duration(milliseconds: 100));
      // 防抖时间到，状态已同步
      expect(state.get('debounced_input'), 'fast typing');
    });

    testWidgets('TextField didUpdateWidget 保留合理光标位置 (P3-5)', (tester) async {
      final state = DuiState();
      final handler =
          DuiEventHandler(state: state, executor: MockActionExecutor());
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
        find.descendant(
            of: textFieldFinder, matching: find.byType(EditableText)),
      );
      editableText.controller.selection =
          const TextSelection.collapsed(offset: 3);

      // 外部更新文本为较长字符串，光标应维持在 3
      state.set('text_ref', '12345678');
      await tester.pump();
      expect(editableText.controller.selection.baseOffset, 3);

      // 外部更新文本为较短字符串，光标应被 clamp 到短字符串长度
      state.set('text_ref', '12');
      await tester.pump();
      expect(editableText.controller.selection.baseOffset, 2);
    });

    testWidgets(
        'TextField didUpdateWidget 在输入法组合态 (isComposingRangeValid) 下不覆盖输入',
        (tester) async {
      final state = DuiState();
      final handler =
          DuiEventHandler(state: state, executor: MockActionExecutor());
      final renderer = DuiRenderer(state: state, eventHandler: handler);

      final node = {
        'type': 'TextField',
        'ref': 'composing_ref',
        'props': {},
      };

      await tester.pumpWidget(buildHost(renderer, node));
      final textFieldFinder = find.byType(TextField);
      final editableText = tester.widget<EditableText>(
        find.descendant(
            of: textFieldFinder, matching: find.byType(EditableText)),
      );

      // 模拟输入法正在拼音打字中 (设置 composing range 为 [0, 4])
      editableText.controller.value = const TextEditingValue(
        text: 'piny',
        composing: TextRange(start: 0, end: 4),
        selection: TextSelection.collapsed(offset: 4),
      );

      // 外部异步状态尝试更新，应被组合态保护拦截
      state.set('composing_ref', 'external');
      await tester.pump();
      expect(editableText.controller.text, 'piny');
    });

    test('DuiState extractKeys 与 key-level 局部通知 (P2-1)', () {
      final state = DuiState();
      expect(
          DuiState.extractKeys('Hello {{state.user}}, count: {{state.count}}'),
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

    test('DuiState 细粒度精准通知与避免全局级联触发', () {
      final state = DuiState();
      int globalNotified = 0;
      int keyNotified = 0;
      state.addListener(() => globalNotified++);
      state.listenableForKey('name').addListener(() => keyNotified++);

      state.set('name', 'Bob');
      expect(keyNotified, 1);
      expect(globalNotified, 0); // 局部 set 默认不击穿全局监听

      state.set('name', 'Charlie', notifyGlobal: true);
      expect(keyNotified, 2);
      expect(globalNotified, 1);

      state.reset({'name': 'Dave'});
      expect(keyNotified, 3);
      expect(globalNotified, 2);
      expect(state.get('name'), 'Dave');
    });

    testWidgets(
        'DuiRenderer 渲染 Switch、Slider、Dropdown、ProgressBar、Divider 与 Wrap 组件及双向绑定',
        (tester) async {
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

      state.set(
          'md_text', '# 标题一\n> 引用说明\n- 列表项\n```dart\nvoid main() {}\n```');

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

    testWidgets('DuiRenderer 渲染 Canvas 动态画板并支持状态指令响应刷新', (tester) async {
      final state = DuiState();
      final executor = MockActionExecutor();
      final handler = DuiEventHandler(state: state, executor: executor);
      final renderer = DuiRenderer(state: state, eventHandler: handler);

      state.set('canvas_cmds',
          '[{"type":"line","x1":0,"y1":0,"x2":50,"y2":50,"color":"#788CFF"}]');

      final node = {
        'type': 'Canvas',
        'props': {
          'width': 200,
          'height': 150,
          'backgroundColor': '#1B2445',
          'commands': '{{state.canvas_cmds}}',
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

      expect(find.byType(DuiCanvas), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);

      // 更新画板指令
      state.set('canvas_cmds',
          '[{"type":"circle","cx":20,"cy":20,"radius":10,"color":"#FF0000"}]');
      await tester.pump();
      expect(find.byType(DuiCanvas), findsOneWidget);
    });

    testWidgets('DuiRenderer 渲染 SignaturePad 并支持手势绘制与清空触发', (tester) async {
      final state = DuiState();
      state.set('clear_tick', 0);
      final executor = MockActionExecutor();
      final eventHandler = DuiEventHandler(state: state, executor: executor);
      final renderer = DuiRenderer(state: state, eventHandler: eventHandler);

      final node = {
        'type': 'SignaturePad',
        'ref': 'my_sign',
        'props': {
          'width': 300.0,
          'height': 200.0,
          'strokeWidth': 4.0,
          'strokeColor': '#000000',
          'clearTrigger': '{{state.clear_tick}}',
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

      expect(find.byType(DuiDrawingPad), findsOneWidget);
      expect(state.get('my_sign_has_drawing'), false);

      // 模拟手势绘制一条线
      final gesture = await tester
          .startGesture(tester.getCenter(find.byType(DuiDrawingPad)));
      await gesture.moveBy(const Offset(50, 50));
      await gesture.up();
      await tester.pump();

      expect(state.get('my_sign_has_drawing'), true);
      expect(state.get('my_sign_count'), 1);

      // 触发清空
      state.set('clear_tick', 1);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => renderer.buildWidget(context, node),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(state.get('my_sign_has_drawing'), false);
      expect(state.get('my_sign_count'), 0);
    });

    testWidgets('DuiRenderer 渲染 Chart (折线图与柱状图) 并支持状态插值', (tester) async {
      final state = DuiState();
      final executor = MockActionExecutor();
      final handler = DuiEventHandler(state: state, executor: executor);
      final renderer = DuiRenderer(state: state, eventHandler: handler);

      state.set('chart_points', '[10, 25, 40, 15, 30]');

      final lineNode = {
        'type': 'Chart',
        'props': {
          'type': 'line',
          'data': '{{state.chart_points}}',
          'labels': 'A,B,C,D,E',
          'color': '#788CFF',
          'height': 180,
        },
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => renderer.buildWidget(context, lineNode),
            ),
          ),
        ),
      );

      expect(find.byType(DuiChart), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);

      // 更新状态数据
      state.set('chart_points', '[5, 15, 60, 20, 50]');
      await tester.pump();
      expect(find.byType(DuiChart), findsOneWidget);

      // 测试柱状图
      final barNode = {
        'type': 'BarChart',
        'props': {
          'data': [100, 200, 300],
          'labels': ['Mon', 'Tue', 'Wed'],
          'color': '#31D9D0',
        },
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => renderer.buildWidget(context, barNode),
            ),
          ),
        ),
      );

      expect(find.byType(DuiChart), findsOneWidget);
    });

    testWidgets('DuiRenderer 渲染 Html 富文本并支持标签解析与链接事件', (tester) async {
      final state = DuiState();
      final executor = MockActionExecutor();
      final handler = DuiEventHandler(state: state, executor: executor);
      final renderer = DuiRenderer(state: state, eventHandler: handler);

      state.set('user_name', 'Alice');

      final node = {
        'type': 'Html',
        'props': {
          'html':
              '<b>你好</b> {{state.user_name}}，<a href="https://example.com">点击这里</a> 查看详情。',
        },
        'events': {
          'onLinkTap': {'action': 'toast', 'message': 'link clicked'},
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

      expect(find.byType(DuiHtml), findsOneWidget);
      expect(find.byType(SelectableText), findsOneWidget);

      // 验证富文本内容被正确插值与解析
      final selectableWidget =
          tester.widget<SelectableText>(find.byType(SelectableText));
      expect(selectableWidget.data,
          isNull); // rich 模式 data 为 null，textSpan 不为 null
      expect(selectableWidget.textSpan, isNotNull);
      final textSpan = selectableWidget.textSpan!;
      final fullText = textSpan.toPlainText();
      expect(fullText.contains('你好'), isTrue);
      expect(fullText.contains('Alice'), isTrue);
      expect(fullText.contains('点击这里'), isTrue);
    });

    testWidgets('DuiHtml、DuiChart 与 DuiCanvas 异常与边界输入安全容错降级', (tester) async {
      final state = DuiState();
      final executor = MockActionExecutor();
      final handler = DuiEventHandler(state: state, executor: executor);
      final renderer = DuiRenderer(state: state, eventHandler: handler);

      // 1. DuiHtml 异常格式
      final malformedHtmlNode = {
        'type': 'Html',
        'props': {
          'html': '<b>未闭合标签<i>混合文本',
        },
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) =>
                  renderer.buildWidget(context, malformedHtmlNode),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(DuiHtml), findsOneWidget);

      // 2. DuiChart 损坏数据
      final corruptedChartNode = {
        'type': 'Chart',
        'props': {
          'data': 'not-a-json-list',
        },
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) =>
                  renderer.buildWidget(context, corruptedChartNode),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(DuiChart), findsOneWidget);

      // 3. DuiCanvas 损坏指令
      final corruptedCanvasNode = {
        'type': 'Canvas',
        'props': {
          'commands': 'invalid-json-commands',
        },
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) =>
                  renderer.buildWidget(context, corruptedCanvasNode),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(DuiCanvas), findsOneWidget);
    });

    testWidgets('DuiNodeErrorBoundary 组件工厂抛出异常时局部降级显示错误占位而不会崩溃整页',
        (tester) async {
      final state = DuiState();
      final executor = MockActionExecutor();
      final eventHandler = DuiEventHandler(state: state, executor: executor);
      final renderer = DuiRenderer(state: state, eventHandler: eventHandler);

      // 注册一个故意抛出异常的工厂组件
      renderer.registerFactory('BrokenWidget', (ctx) {
        throw const FormatException('Malformed config data');
      });

      final rootNode = {
        'type': 'Column',
        'children': [
          {
            'type': 'Text',
            'props': {'text': '正常的组件'},
          },
          {
            'type': 'BrokenWidget',
          },
          {
            'type': 'FilledButton',
            'props': {'text': '可交互按钮'},
          },
        ],
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => renderer.build(context, rootNode),
            ),
          ),
        ),
      );

      // 页面正常渲染，未抛出阻断异常
      expect(tester.takeException(), isNull);
      // 正常组件与按钮均存在
      expect(find.text('正常的组件'), findsOneWidget);
      expect(find.text('可交互按钮'), findsOneWidget);
      // 故障组件局部降级为 DuiErrorPlaceholder
      expect(find.byType(DuiErrorPlaceholder), findsOneWidget);
      expect(find.textContaining('BrokenWidget'), findsOneWidget);
    });

    testWidgets('DUI 畸形 AST 对抗性模糊测试 (Fuzzing): 异常类型、缺失属性与非法结构均优雅局部降级',
        (tester) async {
      final state = DuiState();
      final executor = MockActionExecutor();
      final eventHandler = DuiEventHandler(state: state, executor: executor);
      final renderer = DuiRenderer(state: state, eventHandler: eventHandler);

      final malformedRoot = {
        'type': 'Column',
        'children': [
          // 1. 正常组件
          {
            'type': 'Text',
            'props': {'text': '首部正常文本'},
          },
          // 2. 缺失 type 字段
          <String, dynamic>{},
          // 3. 非法的 type 类型 (数字)
          {'type': 99999},
          // 4. 未知未注册的组件类型
          {'type': 'NoSuchCustomComponentXYZ'},
          // 5. props 为非 Map 的非法类型 (字符串)
          {
            'type': 'Text',
            'props': 'invalid_props_string',
          },
          // 6. children 为非 List 的非法类型
          {
            'type': 'Row',
            'children': 'invalid_children_string',
          },
          // 7. children 列表中掺杂 null 与基础标量
          {
            'type': 'Column',
            'children': [
              null,
              123,
              'garbage_string',
              {
                'type': 'Text',
                'props': {'text': '嵌套正常子项'},
              },
            ],
          },
          // 8. 属性类型严重错乱 (ProgressBar 要求 double/num，给出错乱对象)
          {
            'type': 'ProgressBar',
            'props': {'value': 'not_a_number'},
          },
          // 9. Slider 属性反向 (min > max)
          {
            'type': 'Slider',
            'props': {'value': 50.0, 'min': 100.0, 'max': 0.0},
          },
          // 10. 尾部正常组件
          {
            'type': 'FilledButton',
            'props': {'text': '尾部可用按钮'},
          },
        ],
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => renderer.build(context, malformedRoot),
            ),
          ),
        ),
      );

      // 绝无未捕获异常抛出导致崩溃
      expect(tester.takeException(), isNull);
      // 头部和尾部正常组件均可稳定渲染并可交互
      expect(find.text('首部正常文本'), findsOneWidget);
      expect(find.text('尾部可用按钮'), findsOneWidget);
      expect(find.text('嵌套正常子项'), findsOneWidget);
    });

    test('DuiState 深层点号路径解析、插值、比较与持久化通知', () {
      final state = DuiState();
      state.set('profile', {
        'name': 'Antigravity',
        'details': {
          'age': 25,
          'city': 'Hangzhou',
        },
        'skills': ['Dart', 'Flutter', 'Lua'],
      });

      // 1. 深层路径读取
      expect(state.get('profile.name'), 'Antigravity');
      expect(state.get('profile.details.age'), 25);
      expect(state.get('profile.skills.0'), 'Dart');
      expect(state.get('profile.skills.2'), 'Lua');
      expect(state.get('profile.skills.99'), isNull);
      expect(state.get('profile.nonexistent'), isNull);

      // 2. 模板插值
      const template =
          '用户: {{state.profile.name}}, 城市: {{state.profile.details.city}}, 主语言: {{state.profile.skills.0}}';
      expect(
        state.interpolate(template),
        '用户: Antigravity, 城市: Hangzhou, 主语言: Dart',
      );

      // 3. 依赖提取（顶级与全路径）
      final keys = DuiState.extractKeys(template);
      expect(keys.contains('profile'), isTrue);
      expect(keys.contains('profile.name'), isTrue);
      expect(keys.contains('profile.details.city'), isTrue);

      // 4. 可见性条件计算
      expect(state.evaluateVisible('state.profile.details.age >= 18'), isTrue);
      expect(state.evaluateVisible('state.profile.details.age < 18'), isFalse);
      expect(
          state.evaluateVisible("state.profile.name == 'Antigravity'"), isTrue);

      // 5. 声明式自动持久化通知
      final persisted = <String, dynamic>{};
      state.persistentKeys.add('counter');
      state.onPersist = (k, v) => persisted[k] = v;

      state.set('other', 123);
      expect(persisted.containsKey('other'), isFalse);

      state.set('counter', 42);
      expect(persisted['counter'], 42);
    });
  });
}
