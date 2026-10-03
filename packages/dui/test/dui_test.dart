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
}
