import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_toolbox_dui/plugin_toolbox_dui.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockActionExecutor implements DuiActionExecutor {
  final List<String> calledFunctions = [];
  final List<dynamic> calledArgs = [];

  @override
  void callLua(String functionName, [List<dynamic> args = const []]) {
    calledFunctions.add(functionName);
    calledArgs.addAll(args);
  }

  @override
  void showToast(String message) {}
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('DuiCodeView 组件', () {
    testWidgets('渲染多行代码与行号', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DuiCodeView(
              text: 'local x = 10\nlocal y = 20\nprint(x + y)',
              language: 'lua',
              showLineNumbers: true,
            ),
          ),
        ),
      );

      expect(find.byType(DuiCodeView), findsOneWidget);
      expect(find.text('1\n2\n3'), findsOneWidget);
      expect(find.byType(SelectableText), findsOneWidget);
    });

    testWidgets('空文本安全渲染且不崩溃', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DuiCodeView(text: '', language: 'plaintext'),
          ),
        ),
      );

      expect(find.byType(DuiCodeView), findsOneWidget);
    });

    testWidgets('点击复制按钮触发剪贴板写入与回调', (tester) async {
      var copied = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DuiCodeView(
              text: 'hello world',
              showCopyButton: true,
              onCopy: () {
                copied = true;
              },
            ),
          ),
        ),
      );

      final copyBtn = find.byIcon(Icons.copy);
      expect(copyBtn, findsOneWidget);
      await tester.tap(copyBtn);
      await tester.pumpAndSettle();

      expect(copied, isTrue);
    });
  });

  group('DuiDiffView 组件', () {
    testWidgets('比对两段文本并正确渲染差异行与统计', (tester) async {
      const oldCode = 'function foo()\n  return 1\nend';
      const newCode = 'function foo()\n  return 2\n  -- extra\nend';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DuiDiffView(
              oldText: oldCode,
              newText: newCode,
              showLineNumbers: true,
              showSummary: true,
            ),
          ),
        ),
      );

      expect(find.byType(DuiDiffView), findsOneWidget);
      expect(find.text('文本比对'), findsOneWidget);
      expect(find.text('+2'), findsOneWidget);
      expect(find.text('-1'), findsOneWidget);
    });

    testWidgets('空文本比对容错不崩溃', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DuiDiffView(oldText: '', newText: ''),
          ),
        ),
      );

      expect(find.byType(DuiDiffView), findsOneWidget);
      expect(find.text('+0'), findsOneWidget);
      expect(find.text('-0'), findsOneWidget);
    });
  });

  group('DuiTreeView 组件', () {
    testWidgets('自动将 Map/JSON 解析为折叠树并支持展开', (tester) async {
      final sampleData = {
        'name': 'plugin-toolbox',
        'version': '1.0.0',
        'config': {
          'theme': 'dark',
          'enabled': true,
        },
      };

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DuiTreeView(data: sampleData),
          ),
        ),
      );

      expect(find.byType(DuiTreeView), findsOneWidget);
      expect(find.text('name'), findsOneWidget);
      expect(find.text('version'), findsOneWidget);
      expect(find.text('config'), findsOneWidget);

      // 点击 config 节点进行展开
      final configFinder = find.text('config');
      await tester.tap(configFinder);
      await tester.pumpAndSettle();

      expect(find.text('theme'), findsOneWidget);
      expect(find.text('enabled'), findsOneWidget);
    });

    testWidgets('显式 TreeNode 列表渲染与点击回调', (tester) async {
      Map<String, dynamic>? clicked;
      final explicitTree = [
        {
          'label': '根节点',
          'value': 'root_val',
          'children': [
            {'label': '子节点 1', 'value': 'child_1'},
          ],
        }
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DuiTreeView(
              data: explicitTree,
              expandAll: true,
              onNodeClick: (info) {
                clicked = info;
              },
            ),
          ),
        ),
      );

      expect(find.text('根节点'), findsOneWidget);
      expect(find.text('子节点 1'), findsOneWidget);

      await tester.tap(find.text('子节点 1'));
      await tester.pumpAndSettle();

      expect(clicked, isNotNull);
      expect(clicked?['label'], '子节点 1');
      expect(clicked?['value'], 'child_1');
    });

    testWidgets('空数据展示占位提示', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DuiTreeView(data: null),
          ),
        ),
      );

      expect(find.text('无树形数据'), findsOneWidget);
    });
  });

  group('DuiColorPicker 组件', () {
    testWidgets('渲染色彩预览、预设色块与 RGB 滑块', (tester) async {
      String? changedColor;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DuiColorPicker(
              value: '#788CFF',
              onChanged: (c) {
                changedColor = c;
              },
            ),
          ),
        ),
      );

      expect(find.byType(DuiColorPicker), findsOneWidget);
      expect(find.text('#788CFF'), findsNWidgets(2));

      // 点击预设调色板中的色块
      final swatch = find.byType(GestureDetector).first;
      await tester.tap(swatch);
      await tester.pumpAndSettle();

      expect(changedColor, isNotNull);
    });

    testWidgets('滑动 R 通道滑块更新颜色', (tester) async {
      String? changedColor;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DuiColorPicker(
              value: '#000000',
              showSliders: true,
              onChanged: (c) {
                changedColor = c;
              },
            ),
          ),
        ),
      );

      final slider = find.byType(Slider).first;
      await tester.drag(slider, const Offset(100, 0));
      await tester.pumpAndSettle();

      expect(changedColor, isNotNull);
      expect(changedColor, isNot('#000000'));
    });
  });

  group('DuiRenderer 声明式渲染与数据绑定', () {
    testWidgets('DuiRenderer 渲染 CodeView、DiffView、TreeView 与 ColorPicker',
        (tester) async {
      final state = DuiState();
      state.set('code_content', 'print("hello lua")');
      state.set('old_content', 'line 1');
      state.set('new_content', 'line 2');
      state.set('selected_color', '#31D9D0');

      final executor = MockActionExecutor();
      final eventHandler = DuiEventHandler(executor: executor, state: state);
      final renderer = DuiRenderer(state: state, eventHandler: eventHandler);

      final ast = {
        'type': 'Column',
        'children': [
          {
            'type': 'CodeView',
            'props': {
              'text': '{{state.code_content}}',
              'language': 'lua',
            },
          },
          {
            'type': 'DiffView',
            'props': {
              'oldText': '{{state.old_content}}',
              'newText': '{{state.new_content}}',
            },
          },
          {
            'type': 'TreeView',
            'props': {
              'data': '{"key": "value"}',
            },
          },
          {
            'type': 'ColorPicker',
            'props': {
              'value': '{{state.selected_color}}',
            },
          },
        ],
      };

      // 使用 Builder 构建 context
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => SingleChildScrollView(
                child: renderer.build(ctx, ast),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(DuiCodeView), findsOneWidget);
      expect(find.byType(DuiDiffView), findsOneWidget);
      expect(find.byType(DuiTreeView), findsOneWidget);
      expect(find.byType(DuiColorPicker), findsOneWidget);
      expect(find.text('#31D9D0'), findsNWidgets(2));

      // 验证 CodeView 响应式更新
      state.set('code_content', 'local updated = true');
      await tester.pumpAndSettle();
      expect(find.text('local updated = true'), findsOneWidget);
    });
  });
}
