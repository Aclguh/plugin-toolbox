import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_toolbox/src/app.dart';
import 'package:plugin_toolbox/src/home/home_page.dart';
import 'package:plugin_toolbox/src/plugin_manager/plugin_manager_page.dart';
import 'package:plugin_toolbox/src/providers/app_providers.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';
import 'package:reorderable_grid_view/reorderable_grid_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  ToolPlugin createMockPlugin(String id, String name) {
    return DynamicPlugin(
      manifest: PluginManifest(
        id: id,
        name: name,
        version: '1.0.0',
        description: 'Description for $name',
        author: 'Tester',
        type: 'lua',
        category: PluginCategory.calculator,
        permissions: [],
        entry: 'entry.lua',
        ui: 'ui.json',
      ),
      rootDir: Directory('.'),
    );
  }

  testWidgets('App launches and renders title smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: PluginToolboxApp(),
      ),
    );

    expect(find.text('PluginToolbox'), findsOneWidget);
  });

  testWidgets('HomePage renders plugins in ReorderableGridView without category headers',
      (WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [
        appInitFutureProvider.overrideWith((ref) async {}),
      ],
    );
    final registry = container.read(pluginRegistryProvider);
    registry.register(createMockPlugin('p1', 'Plugin 1'));
    registry.register(createMockPlugin('p2', 'Plugin 2'));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: HomePage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify plugins are displayed
    expect(find.text('Plugin 1'), findsOneWidget);
    expect(find.text('Plugin 2'), findsOneWidget);

    // Verify ReorderableGridView is used
    expect(find.byType(ReorderableGridView), findsOneWidget);

    // Verify NO category SectionHeaders are present
    expect(find.text(PluginCategory.calculator.label), findsNothing);
  });

  testWidgets('PluginManagerPage has left drag handle, switch, no trash icon, and long-press delete dialog',
      (WidgetTester tester) async {
    final container = ProviderContainer();
    final registry = container.read(pluginRegistryProvider);
    registry.register(createMockPlugin('p1', 'Plugin 1'));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: PluginManagerPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify drag indicator icon on left
    expect(find.byIcon(Icons.drag_indicator), findsOneWidget);

    // Verify ReorderableDelayedDragStartListener is present
    expect(find.byType(ReorderableDelayedDragStartListener), findsOneWidget);

    // Verify switch is present
    expect(find.byType(Switch), findsOneWidget);

    // Verify trash can icon is removed
    expect(find.byIcon(Icons.delete_outline), findsNothing);

    // Long press on card body to trigger delete confirmation dialog
    await tester.longPress(find.text('Plugin 1'));
    await tester.pumpAndSettle();

    // Verify delete confirmation dialog appeared
    expect(find.text('卸载插件'), findsOneWidget);
    expect(find.text('确定要卸载插件「Plugin 1」吗？\n卸载后相关数据将被清除。'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('卸载'), findsOneWidget);

    // Tap cancel to dismiss dialog
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(find.text('卸载插件'), findsNothing);
  });

  testWidgets('Order is synchronized between HomePage and PluginManagerPage',
      (WidgetTester tester) async {
    final container = ProviderContainer();
    final registry = container.read(pluginRegistryProvider);
    final notifier = container.read(pluginRegistryProvider.notifier);

    registry.register(createMockPlugin('p1', 'Plugin 1'));
    registry.register(createMockPlugin('p2', 'Plugin 2'));
    registry.register(createMockPlugin('p3', 'Plugin 3'));

    expect(registry.allPlugins.map((p) => p.id).toList(), ['p1', 'p2', 'p3']);
    expect(registry.enabledPlugins.map((p) => p.id).toList(), ['p1', 'p2', 'p3']);

    // Reorder from Manager (move p3 to index 0)
    await notifier.reorder(2, 0);
    expect(registry.allPlugins.map((p) => p.id).toList(), ['p3', 'p1', 'p2']);
    expect(registry.enabledPlugins.map((p) => p.id).toList(), ['p3', 'p1', 'p2']);

    // Reorder from Home (move p2 to index 0)
    await notifier.reorderEnabled(2, 0);
    expect(registry.allPlugins.map((p) => p.id).toList(), ['p2', 'p3', 'p1']);
    expect(registry.enabledPlugins.map((p) => p.id).toList(), ['p2', 'p3', 'p1']);
  });
}
