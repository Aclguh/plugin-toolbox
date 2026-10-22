import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_toolbox_dui/plugin_toolbox_dui.dart';

/// 单子节点 `child` 兼容性测试。
///
/// 规范 AST 使用 `children: [...]`，但生态中手写插件常见 `child: {...}` 写法。
/// 渲染器需将其等价为单元素 children，否则整页会静默渲染为空白。
class _NoopExecutor implements DuiActionExecutor {
  @override
  void callLua(String functionName, [List<dynamic> args = const []]) {}

  @override
  void showToast(String message) {}
}

void main() {
  late DuiState state;
  late DuiEventHandler handler;
  late DuiRenderer renderer;

  setUp(() {
    state = DuiState();
    handler = DuiEventHandler(state: state, executor: _NoopExecutor());
    renderer = DuiRenderer(state: state, eventHandler: handler);
  });

  Widget host(Map<String, dynamic> node) => MaterialApp(
        home: Scaffold(
          body: Builder(builder: (context) => renderer.build(context, node)),
        ),
      );

  testWidgets('单 child 写法等价于单元素 children', (tester) async {
    await tester.pumpWidget(host({
      'type': 'SingleChildScrollView',
      'props': {'padding': 8},
      'child': {
        'type': 'Text',
        'props': {'text': '来自单子节点'},
      },
    }));

    expect(tester.takeException(), isNull);
    expect(find.text('来自单子节点'), findsOneWidget);
  });

  testWidgets('children 与 child 同时存在时以 children 为准', (tester) async {
    await tester.pumpWidget(host({
      'type': 'Column',
      'children': [
        {
          'type': 'Text',
          'props': {'text': 'children 优先'},
        },
      ],
      'child': {
        'type': 'Text',
        'props': {'text': 'child 被忽略'},
      },
    }));

    expect(find.text('children 优先'), findsOneWidget);
    expect(find.text('child 被忽略'), findsNothing);
  });
}
