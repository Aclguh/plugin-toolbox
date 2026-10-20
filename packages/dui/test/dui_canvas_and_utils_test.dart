import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_toolbox_dui/plugin_toolbox_dui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('DuiUtils 基础工具与容错解析', () {
    test('parseIcon 命中与回退语义分析', () {
      expect(DuiUtils.parseIcon(null), Icons.extension);
      expect(DuiUtils.parseIcon(''), Icons.extension);
      expect(DuiUtils.parseIcon('   '), Icons.extension);
      expect(DuiUtils.parseIcon('code'), Icons.code);
      expect(DuiUtils.parseIcon('qr_code'), Icons.qr_code);

      // 回退语义
      expect(DuiUtils.parseIcon('my_timer_widget'), Icons.timer);
      expect(DuiUtils.parseIcon('clock_time'), Icons.access_time);
      expect(DuiUtils.parseIcon('safe_lock'), Icons.lock);
      expect(DuiUtils.parseIcon('math_calc'), Icons.calculate);
      expect(DuiUtils.parseIcon('paint_color'), Icons.palette);
      expect(DuiUtils.parseIcon('trans_lang'), Icons.translate);
      expect(DuiUtils.parseIcon('doc_file'), Icons.description);
      expect(DuiUtils.parseIcon('dir_folder'), Icons.folder);
      expect(DuiUtils.parseIcon('done_check'), Icons.check);
      expect(DuiUtils.parseIcon('cancel_close'), Icons.close);
      expect(DuiUtils.parseIcon('find_search'), Icons.search);
      expect(DuiUtils.parseIcon('write_edit'), Icons.edit);
      expect(DuiUtils.parseIcon('alert_warn'), Icons.warning);
      expect(DuiUtils.parseIcon('fail_error'), Icons.error);
      expect(DuiUtils.parseIcon('info_item'), Icons.info);
      expect(DuiUtils.parseIcon('graph_chart'), Icons.bar_chart);
      expect(DuiUtils.parseIcon('pic_photo'), Icons.image);
      expect(DuiUtils.parseIcon('build_tool'), Icons.build);
      expect(DuiUtils.parseIcon('net_wifi'), Icons.wifi);
      expect(DuiUtils.parseIcon('blue_tooth'), Icons.bluetooth);
      expect(
          DuiUtils.parseIcon('completely_unknown_icon_name'), Icons.extension);
    });

    test('parseColor 容错解析', () {
      expect(DuiUtils.parseColor(null), isNull);
      expect(DuiUtils.parseColor(''), isNull);
      expect(DuiUtils.parseColor('invalid'), isNull);
      expect(DuiUtils.parseColor('#RGB'), isNull);
      expect(DuiUtils.parseColor('#FF0000'), const Color(0xFFFF0000));
      expect(DuiUtils.parseColor('FF0000'), const Color(0xFFFF0000));
      expect(DuiUtils.parseColor('#80FF0000'), const Color(0x80FF0000));
    });

    test('parsePadding 数值、字符串与 Map 复合解析', () {
      expect(DuiUtils.parsePadding(null), EdgeInsets.zero);
      expect(DuiUtils.parsePadding(12), const EdgeInsets.all(12.0));
      expect(DuiUtils.parsePadding('16'), const EdgeInsets.all(16.0));
      expect(DuiUtils.parsePadding('invalid'), EdgeInsets.zero);
      expect(
        DuiUtils.parsePadding({'left': 5, 'top': 6, 'right': 7, 'bottom': 8}),
        const EdgeInsets.only(left: 5, top: 6, right: 7, bottom: 8),
      );
      expect(DuiUtils.parsePadding([]), EdgeInsets.zero);
    });

    test('tryDouble / tryInt / tryBool 类型边界转换', () {
      expect(DuiUtils.tryDouble(null), isNull);
      expect(DuiUtils.tryDouble(3.14), 3.14);
      expect(DuiUtils.tryDouble('42.5'), 42.5);
      expect(DuiUtils.tryDouble('invalid'), isNull);

      expect(DuiUtils.tryInt(null), isNull);
      expect(DuiUtils.tryInt(100), 100);
      expect(DuiUtils.tryInt('200'), 200);
      expect(DuiUtils.tryInt('invalid'), isNull);

      expect(DuiUtils.tryBool(null), isFalse);
      expect(DuiUtils.tryBool(null, fallback: true), isTrue);
      expect(DuiUtils.tryBool(true), isTrue);
      expect(DuiUtils.tryBool(false), isFalse);
      expect(DuiUtils.tryBool('true'), isTrue);
      expect(DuiUtils.tryBool('TRUE'), isTrue);
      expect(DuiUtils.tryBool('false'), isFalse);
      expect(DuiUtils.tryBool(1), isTrue);
      expect(DuiUtils.tryBool(0), isFalse);
    });

    testWidgets('parseTextStyle 样式映射与回退', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (context) {
          ctx = context;
          return const SizedBox();
        }),
      ));

      expect(DuiUtils.parseTextStyle(ctx, null), isNull);
      expect(DuiUtils.parseTextStyle(ctx, 'unknownStyle'), isNull);
      expect(DuiUtils.parseTextStyle(ctx, 'displayLarge'), isNotNull);
      expect(DuiUtils.parseTextStyle(ctx, 'headlineMedium'), isNotNull);
      expect(DuiUtils.parseTextStyle(ctx, 'titleSmall'), isNotNull);
      expect(DuiUtils.parseTextStyle(ctx, 'bodyLarge'), isNotNull);
      expect(DuiUtils.parseTextStyle(ctx, 'bodySmall'), isNotNull);
      expect(DuiUtils.parseTextStyle(ctx, 'labelLarge'), isNotNull);
    });
  });

  group('DuiCanvas 指令画板组件与 Painter', () {
    testWidgets('DuiCanvas 渲染空指令与 List 指令集', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: DuiCanvas(
            width: 200,
            height: 200,
            commands: null,
          ),
        ),
      ));
      expect(find.byType(DuiCanvas), findsOneWidget);

      final commands = [
        {
          'type': 'line',
          'x1': 10,
          'y1': 10,
          'x2': 100,
          'y2': 100,
          'color': '#FF0000',
          'strokeWidth': 2
        },
        {
          'type': 'rect',
          'x': 20,
          'y': 20,
          'width': 50,
          'height': 50,
          'color': '#00FF00',
          'style': 'stroke',
          'borderRadius': 8
        },
        {
          'type': 'rect',
          'x': 30,
          'y': 30,
          'width': 40,
          'height': 40,
          'style': 'fill'
        },
        {
          'type': 'circle',
          'cx': 80,
          'cy': 80,
          'radius': 25,
          'color': '#0000FF',
          'style': 'stroke'
        },
        {
          'type': 'arc',
          'x': 5,
          'y': 5,
          'width': 80,
          'height': 80,
          'startAngle': 0.0,
          'sweepAngle': 1.5,
          'useCenter': true,
          'style': 'fill'
        },
        {
          'type': 'text',
          'text': 'Test Canvas',
          'x': 15,
          'y': 15,
          'fontSize': 16,
          'color': '#FFFFFF'
        },
        {'type': 'clear', 'color': '#1B2445'},
      ];

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: DuiCanvas(
            width: 200,
            height: 200,
            backgroundColor: Colors.black,
            commands: commands,
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('DuiCanvas 渲染 JSON 字符串指令及缓存命中', (tester) async {
      const jsonStr =
          '[{"type": "line", "x1": 0, "y1": 0, "x2": 50, "y2": 50}]';

      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: DuiCanvas(
            width: 150,
            height: 150,
            commands: jsonStr,
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(DuiCanvas), findsOneWidget);

      // 再次渲染触发缓存
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: DuiCanvas(
            width: 150,
            height: 150,
            commands: jsonStr,
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(DuiCanvas), findsOneWidget);
    });

    test('DuiCanvasPainter shouldRepaint 逻辑校验', () {
      final cmdA = [
        {'type': 'line', 'x1': 0}
      ];
      final cmdB = [
        {'type': 'line', 'x1': 0}
      ];
      final cmdC = [
        {'type': 'line', 'x1': 10}
      ];
      final cmdD = [
        {'type': 'line', 'x1': 0},
        {'type': 'line', 'x1': 1}
      ];

      final painterA = DuiCanvasPainter(cmdA);
      final painterSame = DuiCanvasPainter(cmdA);
      expect(painterA.shouldRepaint(painterSame), isFalse);

      final painterB = DuiCanvasPainter(cmdB);
      expect(painterA.shouldRepaint(painterB), isFalse);

      final painterC = DuiCanvasPainter(cmdC);
      expect(painterA.shouldRepaint(painterC), isTrue);

      final painterD = DuiCanvasPainter(cmdD);
      expect(painterA.shouldRepaint(painterD), isTrue);
    });
  });

  group('DuiMarkdownView 原生 Markdown 渲染组件', () {
    testWidgets('渲染多级标题、代码块、列表与格式化文本', (tester) async {
      const mdContent = '''
# 标题一
## 标题二
### 标题三

---

段落文本包含 **粗体** 与 *斜体* 以及 `inline_code`。

```dart
void main() {
  print("hello");
}
```

- 无序列表项 1
- 无序列表项 2

1. 有序列表项 A
2. 有序列表项 B

> 这是引用文本块
''';

      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DuiMarkdownView(
              data: mdContent,
              selectable: false,
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('标题一', findRichText: true), findsOneWidget);
      expect(find.text('标题二', findRichText: true), findsOneWidget);
      expect(find.text('标题三', findRichText: true), findsOneWidget);
      expect(find.byType(Divider), findsOneWidget);
      expect(find.textContaining('void main()', findRichText: true),
          findsOneWidget);
    });
  });
}
