import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';
import 'package:plugin_toolbox_ui/plugin_toolbox_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 可配置图标名与图标路径的内存桩插件，仅用于验证表现层映射与缓存
class _StubPlugin extends ToolPlugin {
  final String iconNameOverride;
  final String? iconPathOverride;

  _StubPlugin({this.iconNameOverride = 'build', this.iconPathOverride});

  @override
  String get id => 'stub';
  @override
  String get name => 'Stub';
  @override
  String get description => 'stub plugin';
  @override
  String get version => '1.0.0';
  @override
  PluginCategory get category => PluginCategory.other;
  @override
  String get iconName => iconNameOverride;
  @override
  String? get iconPath => iconPathOverride;
  @override
  Future<void> initialize(PluginContext context) async {}
  @override
  Future<void> dispose() async {}
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });
  group('UI Theme & Widgets', () {
    test('theme configurations generate valid ThemeData', () {
      final light = AppTheme.light();
      final dark = AppTheme.dark();

      expect(light.useMaterial3, isTrue);
      expect(dark.useMaterial3, isTrue);
      expect(dark.brightness, Brightness.dark);
      expect(dark.scaffoldBackgroundColor, const Color(0xFF26366A));
      expect(dark.colorScheme.surface, const Color(0xFF26366A));
      expect(dark.colorScheme.onSurface, const Color(0xFFB4C9FF));
      // 次级文字色调亮后对卡片底色保持 WCAG AAA (M-6)
      expect(dark.colorScheme.onSurfaceVariant, const Color(0xFF99B2E0));
      expect(dark.cardTheme.clipBehavior, Clip.antiAlias);
      expect((dark.cardTheme.shape as RoundedRectangleBorder).borderRadius,
          BorderRadius.circular(16));
    });

    testWidgets('SectionHeader displays title and trailing widget',
        (tester) async {
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

    testWidgets('PluginCard displays plugin name and description',
        (tester) async {
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
      final card = tester.widget<Card>(find.byType(Card));
      expect(card.clipBehavior, Clip.antiAlias);
      expect(card.margin, EdgeInsets.zero);

      await tester.tap(find.text('Mock Plugin'));
      expect(tapped, isTrue);
    });

    testWidgets('PluginCard 在 iconProvider 缺失时回退矢量图标', (tester) async {
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
            body: PluginCard(plugin: plugin, onTap: () {}),
          ),
        ),
      );

      expect(find.byIcon(plugin.icon), findsOneWidget);
    });

    testWidgets('CopyButton 复制并弹出 SnackBar', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: CopyButton(text: 'copy-me'),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.content_copy));
      await tester.pump();

      expect(find.text('已复制到剪贴板'), findsOneWidget);
    });
  });

  group('ErrorView 主题取色', () {
    testWidgets('错误图标取自 colorScheme.error 而非硬编码色', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(body: ErrorView(message: 'boom')),
        ),
      );

      final icon = tester.widget<Icon>(find.byIcon(Icons.error_outline));
      expect(icon.color, AppColorSchemes.darkScheme.error);
    });
  });

  group('PluginPageScaffold', () {
    testWidgets('展示标题、主体、动作按钮与浮动按钮', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const PluginPageScaffold(
            title: '插件页标题',
            body: Text('主体内容'),
            actions: [Icon(Icons.settings_rounded)],
            floatingActionButton: FloatingActionButton(
              onPressed: null,
              child: Icon(Icons.add),
            ),
          ),
        ),
      );

      expect(find.byType(AppBar), findsOneWidget);
      expect(find.text('插件页标题'), findsOneWidget);
      expect(find.text('主体内容'), findsOneWidget);
      expect(find.byIcon(Icons.settings_rounded), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });

    testWidgets('缺省动作与浮动按钮时不渲染对应槽位', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: PluginPageScaffold(
            title: '简洁页',
            body: Text('仅主体'),
          ),
        ),
      );

      expect(find.text('简洁页'), findsOneWidget);
      expect(find.text('仅主体'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('ToolPluginUiExtension', () {
    test('icon 按名称映射到 Material 矢量图标', () {
      expect(_StubPlugin(iconNameOverride: 'code').icon, Icons.code_rounded);
      expect(
          _StubPlugin(iconNameOverride: 'hash').icon, Icons.security_rounded);
      expect(_StubPlugin(iconNameOverride: 'calculator').icon,
          Icons.calculate_rounded);
      expect(
          _StubPlugin(iconNameOverride: 'qrcode').icon, Icons.qr_code_rounded);
      expect(_StubPlugin(iconNameOverride: 'unknown').icon,
          const IconData(0xe247, fontFamily: 'MaterialIcons'));
    });

    test('iconProvider 无图标路径时直接返回 null', () {
      expect(_StubPlugin().iconProvider, isNull);
    });

    test('iconProvider 命中本地文件时返回 FileImage 且二次调用复用缓存实例', () {
      final tempDir = Directory.systemTemp.createTempSync('pt_icon_hit');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final iconFile = File('${tempDir.path}/icon.png')
        ..writeAsBytesSync(const [137, 80, 78, 71]); // 占位字节, 不触发解码
      final plugin = _StubPlugin(iconPathOverride: iconFile.path);

      invalidatePluginIconCache();
      final first = plugin.iconProvider;
      expect(first, isA<FileImage>());
      // 缓存命中应返回同一实例, 证明 build 期不再重复触盘
      expect(identical(first, plugin.iconProvider), isTrue);
    });

    test('iconProvider 缓存文件缺失结果, 失效钩子触发重新解析', () {
      final tempDir = Directory.systemTemp.createTempSync('pt_icon_miss');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final iconFile = File('${tempDir.path}/icon.png');
      final plugin = _StubPlugin(iconPathOverride: iconFile.path);

      invalidatePluginIconCache();
      expect(plugin.iconProvider, isNull);
      expect(plugin.iconProvider, isNull);

      // 文件补齐后, 未失效前仍命中旧缓存; 显式失效后重新解析出 provider
      iconFile.writeAsBytesSync(const [137, 80, 78, 71]);
      expect(plugin.iconProvider, isNull);
      invalidatePluginIconCache(iconFile.path);
      expect(plugin.iconProvider, isA<FileImage>());
    });
  });
}
