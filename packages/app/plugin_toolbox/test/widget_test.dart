import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_toolbox/src/app.dart';

void main() {
  testWidgets('App launches and renders title smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: PluginToolboxApp(),
      ),
    );

    expect(find.text('PluginToolbox'), findsOneWidget);
  });
}
