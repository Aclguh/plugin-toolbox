import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_toolbox_dui/plugin_toolbox_dui.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockActionExecutor implements DuiActionExecutor {
  final List<String> calledFunctions = [];

  @override
  void callLua(String functionName, [List<dynamic> args = const []]) {
    calledFunctions.add(functionName);
  }

  @override
  void showToast(String message) {}
}

bool hasPixelGridPainter(WidgetTester tester) {
  return tester.widgetList<CustomPaint>(find.byType(CustomPaint)).any(
      (p) => p.painter.runtimeType.toString().endsWith('_PixelGridPainter'));
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('DuiPixelGrid 组件', () {
    testWidgets('按位图与列数渲染确定尺寸的像素画布', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: DuiPixelGrid(data: '010111101', cols: 3, cellSize: 10),
            ),
          ),
        ),
      );

      final sized = tester.widget<SizedBox>(
        find.byWidgetPredicate((w) => w is SizedBox && w.width == 30.0),
      );
      expect(sized.height, 30.0);
      expect(hasPixelGridPainter(tester), isTrue);
    });

    testWidgets('空数据/零列/长度不整除时安全降级为空白不崩溃', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home:
              Scaffold(body: DuiPixelGrid(data: '0101', cols: 3, cellSize: 10)),
        ),
      );
      expect(hasPixelGridPainter(tester), isFalse);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: DuiPixelGrid(data: '', cols: 3, cellSize: 10)),
        ),
      );
      expect(hasPixelGridPainter(tester), isFalse);

      await tester.pumpWidget(
        const MaterialApp(
          home:
              Scaffold(body: DuiPixelGrid(data: '0101', cols: 0, cellSize: 10)),
        ),
      );
      expect(hasPixelGridPainter(tester), isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('PixelGrid 绑定的状态键变化时无需重建宿主即重绘 (回归 #16)', (tester) async {
      final state = DuiState();
      state.set('px', '010111101');
      final handler =
          DuiEventHandler(state: state, executor: MockActionExecutor());
      final renderer = DuiRenderer(state: state, eventHandler: handler);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => renderer.build(context, {
                'type': 'PixelGrid',
                'props': {
                  'data': '{{state.px}}',
                  'cols': '3',
                  'cellSize': '10',
                },
              }),
            ),
          ),
        ),
      );

      DuiPixelGrid grid() =>
          tester.widget<DuiPixelGrid>(find.byType(DuiPixelGrid));
      expect(grid().data, '010111101');
      expect(hasPixelGridPainter(tester), isTrue);

      // 仅写入状态不重建宿主: 订阅生效后网格数据必须即时更新
      state.set('px', '111000111');
      await tester.pump();
      expect(grid().data, '111000111');

      // 更新为与列数不整除的位图 -> 安全降级为空白
      state.set('px', '0101');
      await tester.pump();
      expect(grid().data, '0101');
      expect(hasPixelGridPainter(tester), isFalse);

      // 恢复合法位图 -> 重新绘制
      state.set('px', '101010101');
      await tester.pump();
      expect(hasPixelGridPainter(tester), isTrue);
    });

    testWidgets('PixelGrid 无状态绑定的静态位图直接渲染', (tester) async {
      final state = DuiState();
      final handler =
          DuiEventHandler(state: state, executor: MockActionExecutor());
      final renderer = DuiRenderer(state: state, eventHandler: handler);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => renderer.build(context, {
                'type': 'PixelGrid',
                'props': {'data': '111111111', 'cols': '3', 'cellSize': '8'},
              }),
            ),
          ),
        ),
      );

      expect(find.byType(DuiPixelGrid), findsOneWidget);
      expect(hasPixelGridPainter(tester), isTrue);
    });
  });

  group('DuiMarkdownView 组件', () {
    testWidgets('渲染标题/代码块/列表/引用并默认可选择', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DuiMarkdownView(
                data: '# 大标题\n\n- 列表项\n\n> 引用内容\n\n```\ncode line\n```',
              ),
            ),
          ),
        ),
      );

      expect(find.text('大标题'), findsOneWidget);
      expect(find.text('code line'), findsOneWidget);
      expect(find.text('•'), findsOneWidget);
      expect(find.text('引用内容', findRichText: true), findsOneWidget);
      expect(find.byType(SelectionArea), findsOneWidget);
    });

    testWidgets('selectable=false 时不挂 SelectionArea', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home:
              Scaffold(body: DuiMarkdownView(data: '正文内容', selectable: false)),
        ),
      );

      expect(find.byType(SelectionArea), findsNothing);
      expect(find.text('正文内容', findRichText: true), findsOneWidget);
    });

    testWidgets('未闭合代码块与空数据容错降级不崩溃', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DuiMarkdownView(data: '```\n未闭合代码内容'),
          ),
        ),
      );
      expect(find.text('未闭合代码内容'), findsOneWidget);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: DuiMarkdownView(data: '')),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('DuiDrawingPad 组件', () {
    testWidgets('手势绘制后同步状态计数并触发 onChanged', (tester) async {
      final state = DuiState();
      var changedCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: DuiDrawingPad(
                width: 200,
                height: 120,
                refKey: 'pad',
                state: state,
                onChanged: () => changedCount++,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(DuiDrawingPad), findsOneWidget);
      expect(state.get('pad_has_drawing'), false);

      final gesture = await tester
          .startGesture(tester.getCenter(find.byType(DuiDrawingPad)));
      await gesture.moveBy(const Offset(30, 20));
      await gesture.up();
      await tester.pump();

      expect(state.get('pad_has_drawing'), true);
      expect(state.get('pad_count'), 1);
      expect(changedCount, greaterThan(0));
    });

    testWidgets('clearTrigger 变化时清空笔画并回写状态', (tester) async {
      final state = DuiState();

      Widget host(String trigger) => MaterialApp(
            home: Scaffold(
              body: Center(
                child: DuiDrawingPad(
                  width: 200,
                  height: 120,
                  refKey: 'pad',
                  state: state,
                  clearTrigger: trigger,
                ),
              ),
            ),
          );

      await tester.pumpWidget(host('c0'));
      final gesture = await tester
          .startGesture(tester.getCenter(find.byType(DuiDrawingPad)));
      await gesture.moveBy(const Offset(30, 20));
      await gesture.up();
      await tester.pump();
      expect(state.get('pad_count'), 1);

      await tester.pumpWidget(host('c1'));
      await tester.pump();
      expect(state.get('pad_has_drawing'), false);
      expect(state.get('pad_count'), 0);
    });

    testWidgets('exportTrigger 变化时导出 PNG Base64 并回调', (tester) async {
      final state = DuiState();
      String? exported;

      await tester.runAsync(() async {
        Widget host(String trigger) => MaterialApp(
              home: Scaffold(
                body: Center(
                  child: DuiDrawingPad(
                    width: 120,
                    height: 80,
                    refKey: 'pad',
                    state: state,
                    exportTrigger: trigger,
                    onExport: (b64) => exported = b64,
                  ),
                ),
              ),
            );

        await tester.pumpWidget(host('e0'));
        final gesture = await tester
            .startGesture(tester.getCenter(find.byType(DuiDrawingPad)));
        await gesture.moveBy(const Offset(20, 10));
        await gesture.up();
        await tester.pump();

        await tester.pumpWidget(host('e1'));
        // 光栅化与 PNG 编码为真实异步任务, 等待其完成
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });

      expect(exported, isNotNull);
      expect(exported!.isNotEmpty, isTrue);
      expect(state.get('pad_base64'), exported);
    });
  });

  group('DuiHtml 组件', () {
    testWidgets('嵌套标签 <b><i> 合并样式同时保留粗体与斜体 (回归 #25)', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: DuiHtml(html: '<b><i>粗斜体</i></b>')),
        ),
      );

      final selectable =
          tester.widget<SelectableText>(find.byType(SelectableText));
      TextSpan? target;
      void walk(InlineSpan span) {
        if (span is TextSpan) {
          if (span.text == '粗斜体') target = span;
          span.children?.forEach(walk);
        }
      }

      walk(selectable.textSpan!);
      expect(target, isNotNull);
      expect(target!.style?.fontWeight, FontWeight.bold);
      expect(target!.style?.fontStyle, FontStyle.italic);
    });

    testWidgets('链接点击触发 onLinkTap, 重建与销毁期识别器回收无异常', (tester) async {
      String? tappedUrl;

      Widget host(String html) => MaterialApp(
            home: Scaffold(
              body: DuiHtml(html: html, onLinkTap: (url) => tappedUrl = url),
            ),
          );

      await tester.pumpWidget(host('<a href="https://example.com">链接甲</a>'));
      await tester.tap(find.text('链接甲', findRichText: true));
      expect(tappedUrl, 'https://example.com');

      // html 变更走 didUpdateWidget 失效路径, 旧识别器应在生命周期内回收
      await tester.pumpWidget(host('<b>纯文本</b>'));
      expect(find.text('纯文本', findRichText: true), findsOneWidget);
      expect(tester.takeException(), isNull);

      // 卸载组件, dispose 回收识别器
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('DuiRenderer 预编译节点', () {
    testWidgets('visible 绑定节点随状态键显隐, 兄弟节点不受影响 (#15)', (tester) async {
      final state = DuiState();
      state.set('show_detail', false);
      final handler =
          DuiEventHandler(state: state, executor: MockActionExecutor());
      final renderer = DuiRenderer(state: state, eventHandler: handler);

      final node = {
        'type': 'Column',
        'children': [
          {
            'type': 'Text',
            'props': {'text': '常驻内容'},
          },
          {
            'type': 'Text',
            'visible': '{{state.show_detail}}',
            'props': {'text': '详情内容'},
          },
        ],
      };

      Widget host() => MaterialApp(
            home: Scaffold(
              body:
                  Builder(builder: (context) => renderer.build(context, node)),
            ),
          );

      await tester.pumpWidget(host());
      expect(find.text('常驻内容'), findsOneWidget);
      expect(find.text('详情内容'), findsNothing);

      state.set('show_detail', true);
      await tester.pump();
      expect(find.text('详情内容'), findsOneWidget);
      expect(find.text('常驻内容'), findsOneWidget);

      state.set('show_detail', false);
      await tester.pump();
      expect(find.text('详情内容'), findsNothing);

      // 同一份 AST 实例重复 build 命中预编译缓存, 渲染行为保持一致
      await tester.pumpWidget(host());
      expect(find.text('常驻内容'), findsOneWidget);
      expect(find.text('详情内容'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('visible 为常量 false 的节点不参与渲染', (tester) async {
      final state = DuiState();
      final handler =
          DuiEventHandler(state: state, executor: MockActionExecutor());
      final renderer = DuiRenderer(state: state, eventHandler: handler);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => renderer.build(context, {
                'type': 'Text',
                'visible': false,
                'props': {'text': '不可见'},
              }),
            ),
          ),
        ),
      );

      expect(find.text('不可见'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('Repeater 动态列表数据绑定组件', () {
    testWidgets('基于静态 items 与 itemTemplate 渲染列表项及索引插值', (tester) async {
      final state = DuiState();
      final handler =
          DuiEventHandler(state: state, executor: MockActionExecutor());
      final renderer = DuiRenderer(state: state, eventHandler: handler);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => renderer.build(context, {
                'type': 'Repeater',
                'props': {
                  'items': ['苹果', '香蕉', '橙子'],
                  'spacing': 8.0,
                  'itemTemplate': {
                    'type': 'Text',
                    'props': {'text': r'{{$index}}: {{$item}}'},
                  },
                },
              }),
            ),
          ),
        ),
      );

      expect(find.text('0: 苹果'), findsOneWidget);
      expect(find.text('1: 香蕉'), findsOneWidget);
      expect(find.text('2: 橙子'), findsOneWidget);
    });

    testWidgets('响应式绑定 dataSource 并支持对象字段属性解析与空状态', (tester) async {
      final state = DuiState();
      state.set('todo_list', [
        {'title': '任务A', 'status': '进行中'},
        {'title': '任务B', 'status': '已完成'},
      ]);
      final handler =
          DuiEventHandler(state: state, executor: MockActionExecutor());
      final renderer = DuiRenderer(state: state, eventHandler: handler);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => renderer.build(context, {
                'type': 'Repeater',
                'props': {
                  'dataSource': '{{state.todo_list}}',
                  'emptyText': '暂无代办事项',
                  'itemTemplate': {
                    'type': 'Text',
                    'props': {
                      'text': r'{{$item.title}} - {{$item.status}}',
                    },
                  },
                },
              }),
            ),
          ),
        ),
      );

      expect(find.text('任务A - 进行中'), findsOneWidget);
      expect(find.text('任务B - 已完成'), findsOneWidget);

      // 更新状态列表
      state.set('todo_list', [
        {'title': '任务C', 'status': '已创建'},
      ]);
      await tester.pump();

      expect(find.text('任务A - 进行中'), findsNothing);
      expect(find.text('任务C - 已创建'), findsOneWidget);

      // 清空状态列表
      state.set('todo_list', []);
      await tester.pump();

      expect(find.text('暂无代办事项'), findsOneWidget);
    });
  });
}
