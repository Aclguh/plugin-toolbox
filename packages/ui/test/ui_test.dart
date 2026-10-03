import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';
import 'package:plugin_toolbox_ui/plugin_toolbox_ui.dart';

void main() {
  group('UI Theme & Widgets', () {
    test('theme configurations generate valid ThemeData', () {
      final light = AppTheme.light();
      final dark = AppTheme.dark();

      expect(light.useMaterial3, isTrue);
      expect(dark.useMaterial3, isTrue);
      expect(dark.brightness, Brightness.dark);
    });

    testWidgets('SectionHeader displays title and trailing widget', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SectionHeader(
              title: 'Test Section',
              trailing: Text('More'),
            ),
          ),
        ),
      );

      expect(find.text('Test Section'), findsOneWidget);
      expect(find.text('More'), findsOneWidget);
    });

    testWidgets('ErrorView displays message and retries', (tester) async {
      bool retried = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ErrorView(
              message: 'Failed to load',
              onRetry: () => retried = true,
            ),
          ),
        ),
      );

      expect(find.text('Failed to load'), findsOneWidget);
      await tester.tap(find.text('重试'));
      expect(retried, isTrue);
    });

    testWidgets('PluginCard displays plugin name and description', (tester) async {
      bool tapped = false;
      const manifest = PluginManifest(
        id: 'mock_plugin',
        name: 'Mock Plugin',
        version: '1.0.0',
        description: 'Mock Description',
        author: 'Author',
        type: 'lua',
        category: PluginCategory.other,
        permissions: [],
        entry: 'main.lua',
        ui: 'ui.json',
      );

      final plugin = DynamicPlugin(
        manifest: manifest,
        rootDir: Directory('.'),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PluginCard(
              plugin: plugin,
              onTap: () => tapped = true,
            ),
          ),
        ),
      );

      expect(find.text('Mock Plugin'), findsOneWidget);
      expect(find.text('Mock Description'), findsOneWidget);

      await tester.tap(find.text('Mock Plugin'));
      expect(tapped, isTrue);
    });
  });
}
