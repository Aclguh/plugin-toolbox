import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';
import 'package:plugin_toolbox/src/plugin_host/dynamic_plugin_host_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('ptx_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (methodCall) async {
        if (methodCall.method == 'getApplicationDocumentsDirectory') {
          return tempDir.path;
        }
        return null;
      },
    );
  });

  tearDownAll(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  testWidgets('E2E: Installs base64_tool.ptx and executes encode in DynamicPluginHostPage', (tester) async {
    // 1. Install base64_tool.ptx
    final ptxFile = File('../sample_plugins/base64_tool.ptx').existsSync()
        ? File('../sample_plugins/base64_tool.ptx')
        : File('sample_plugins/base64_tool.ptx');
    expect(ptxFile.existsSync(), isTrue, reason: 'sample_plugins/base64_tool.ptx must exist');

    final dynamicPlugin = await tester.runAsync(() => PluginInstaller.installFromPtx(ptxFile));
    expect(dynamicPlugin, isNotNull);
    expect(dynamicPlugin!.id, 'base64_tool');
    expect(dynamicPlugin.name, 'Base64 编解码');
    expect(dynamicPlugin.category, PluginCategory.encoding);

    // 2. Render dynamic plugin in host page
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: DynamicPluginHostPage(plugin: dynamicPlugin),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Verify UI components rendered by DUI
    expect(find.text('Base64 编解码'), findsOneWidget); // AppBar title
    expect(find.text('编码'), findsOneWidget);
    expect(find.text('解码'), findsOneWidget);

    // 3. Enter text into input field
    final textField = find.byType(TextField);
    expect(textField, findsOneWidget);
    await tester.enterText(textField, 'Hello PluginToolbox!');
    await tester.pump(const Duration(milliseconds: 200));

    // 4. Tap "编码" button
    await tester.tap(find.text('编码'));
    await tester.pump(const Duration(milliseconds: 200));

    // 5. Verify encoded result displayed in DUI
    expect(find.text('SGVsbG8gUGx1Z2luVG9vbGJveCE='), findsOneWidget);

    // 6. Tap swap button
    await tester.tap(find.byTooltip('内容对调'));
    await tester.pump(const Duration(milliseconds: 200));

    // 7. Tap "解码" button
    await tester.tap(find.text('解码'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Hello PluginToolbox!'), findsOneWidget);
  });
}
