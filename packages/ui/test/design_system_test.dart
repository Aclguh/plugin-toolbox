import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_toolbox_ui/plugin_toolbox_ui.dart';

/// 设计系统回归测试。
///
/// 覆盖的是"规范本身"而非具体业务页面：
/// 主题令牌装配、语义色扩展、通用状态组件与交互容器的一致性。
/// 任何一处调整若破坏统一规范（例如某组件圆角漂移、缺失动效配置），
/// 这里会第一时间失败，避免规范在多页面复制粘贴中悄然失效。
void main() {
  group('设计令牌与主题装配', () {
    test('间距 / 圆角 / 动效令牌保持 4dp 栅格与统一节奏', () {
      expect(AppSpacing.sm, 8);
      expect(AppSpacing.lg, 16);
      expect(AppSpacing.xxl, 24);
      expect(AppSpacing.sm * 2, AppSpacing.lg);
      expect(AppSpacing.lg + AppSpacing.sm, AppSpacing.xxl);

      // 同心圆角：卡片 > 按钮 > 徽标
      expect(AppRadius.xl, 16);
      expect(AppRadius.lg, 12);
      expect(AppRadius.xs, 6);
      expect(AppRadius.xl > AppRadius.lg, isTrue);
      expect(AppRadius.lg > AppRadius.xs, isTrue);

      // 动效分档且单调递增，避免出现"点击比转场还慢"的反直觉手感
      expect(AppMotion.instant < AppMotion.fast, isTrue);
      expect(AppMotion.fast < AppMotion.normal, isTrue);
      expect(AppMotion.normal < AppMotion.slow, isTrue);
    });

    test('主题统一装配组件形状、提示与转场', () {
      final dark = AppTheme.dark();
      final light = AppTheme.light();

      for (final theme in [dark, light]) {
        // 卡片圆角为跨页面契约值，不得漂移
        final cardShape = theme.cardTheme.shape as RoundedRectangleBorder;
        expect(
          (cardShape.borderRadius as BorderRadius).topLeft.x,
          AppRadius.xl,
        );
        // 弹窗与卡片使用同心圆角（外大内小）
        final dialogShape = theme.dialogTheme.shape as RoundedRectangleBorder;
        expect(
          (dialogShape.borderRadius as BorderRadius).topLeft.x,
          AppRadius.xxl,
        );
        final inputBorder =
            theme.inputDecorationTheme.border as OutlineInputBorder;
        expect(
          inputBorder.borderRadius.topLeft.x,
          AppRadius.lg,
        );
        expect(theme.inputDecorationTheme.focusedBorder, isNotNull);

        // 提示条统一悬浮样式与圆角
        expect(theme.snackBarTheme.behavior, SnackBarBehavior.floating);
        expect(theme.snackBarTheme.shape, isA<RoundedRectangleBorder>());

        // 全平台统一转场，避免三端观感不一致
        expect(
          theme.pageTransitionsTheme.builders[TargetPlatform.android],
          isA<AppPageTransitionsBuilder>(),
        );
        expect(
          theme.pageTransitionsTheme.builders[TargetPlatform.iOS],
          isA<AppPageTransitionsBuilder>(),
        );

        // 字体层级严格递进
        final text = theme.textTheme;
        expect(
          text.displaySmall!.fontSize! > text.titleLarge!.fontSize!,
          isTrue,
        );
        expect(
          text.titleLarge!.fontSize! > text.bodyMedium!.fontSize!,
          isTrue,
        );
        expect(
          text.bodyMedium!.fontSize! > text.labelSmall!.fontSize!,
          isTrue,
        );
        expect(text.bodyMedium!.height, greaterThan(1));
      }
    });

    test('语义色扩展随亮度切换且与品牌色一致', () {
      expect(AppSemanticColors.dark.success, AppColorSchemes.brandMint);
      expect(AppSemanticColors.dark.warning, AppColorSchemes.brandAmber);
      expect(
          AppSemanticColors.light.success,
          isNot(
            AppSemanticColors.dark.success,
          ));

      final darkTheme = AppTheme.dark();
      final extension = darkTheme.extension<AppSemanticColors>();
      expect(extension, isNotNull);
      expect(extension!.success, AppSemanticColors.dark.success);
      // 亮暗互转插值不抛异常
      expect(extension.lerp(AppSemanticColors.light, 0.5), isNotNull);
    });

    test('网格列数按可用宽度自适应', () {
      expect(AppLayout.gridColumnsFor(360, portrait: true), 3);
      expect(AppLayout.gridColumnsFor(640, portrait: false), 4);
      expect(AppLayout.gridColumnsFor(1000), 5);
      expect(AppLayout.gridColumnsFor(1280), 6);
    });
  });

  group('通用状态与交互组件', () {
    testWidgets('AppBadge 渲染语义徽标', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(
            body: AppBadge(
              label: '可更新',
              tone: AppBadgeTone.warning,
              icon: Icons.system_update_alt_rounded,
            ),
          ),
        ),
      );

      expect(find.text('可更新'), findsOneWidget);
      expect(find.byIcon(Icons.system_update_alt_rounded), findsOneWidget);
    });

    testWidgets('AppBanner 渲染标题、说明与动作', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: AppBanner(
              title: '敏感权限授权提醒',
              message: '相机权限可访问硬件',
              tone: AppBannerTone.danger,
              action: TextButton(
                onPressed: () => tapped = true,
                child: const Text('详情'),
              ),
            ),
          ),
        ),
      );

      expect(find.text('敏感权限授权提醒'), findsOneWidget);
      expect(find.text('相机权限可访问硬件'), findsOneWidget);
      await tester.tap(find.text('详情'));
      expect(tapped, isTrue);
    });

    testWidgets('AppEmptyState 渲染标题、说明与主次操作', (tester) async {
      var primary = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: AppEmptyState(
              icon: Icons.inbox_outlined,
              title: '暂无内容',
              message: '安装插件后即可使用',
              action: FilledButton(
                onPressed: () => primary = true,
                child: const Text('去安装'),
              ),
              secondaryAction: const TextButton(
                onPressed: null,
                child: Text('导入本地包'),
              ),
            ),
          ),
        ),
      );

      expect(find.text('暂无内容'), findsOneWidget);
      expect(find.text('安装插件后即可使用'), findsOneWidget);
      await tester.tap(find.text('去安装'));
      expect(primary, isTrue);
      expect(find.text('导入本地包'), findsOneWidget);
    });

    testWidgets('AppLoadingView 展示进度环与说明文案', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(
            body: AppLoadingView(label: '正在获取插件目录…'),
          ),
        ),
      );
      // 加载环为无限动画，此处只推进单帧而不等待 settle
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('正在获取插件目录…'), findsOneWidget);
    });

    testWidgets('AppDialog 统一弹窗外壳并保留动作回调', (tester) async {
      String? result;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    result = await showDialog<String>(
                      context: context,
                      builder: (ctx) => AppDialog(
                        icon: Icons.help_outline_rounded,
                        title: '确认操作',
                        subtitle: '该操作不可撤销',
                        content: const Text('是否继续？'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop('cancel'),
                            child: const Text('取消'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.of(ctx).pop('ok'),
                            child: const Text('继续'),
                          ),
                        ],
                      ),
                    );
                  },
                  child: const Text('打开弹窗'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开弹窗'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('确认操作'), findsOneWidget);
      expect(find.text('该操作不可撤销'), findsOneWidget);
      expect(find.text('是否继续？'), findsOneWidget);

      await tester.tap(find.text('继续'));
      await tester.pumpAndSettle();
      expect(result, 'ok');
    });

    testWidgets('AppSection 渲染分组标题与条目分隔', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(
            body: AppSection(
              title: '外观与显示',
              subtitle: '主题、旋转与取色',
              icon: Icons.palette_outlined,
              children: [
                ListTile(title: Text('主题模式')),
                ListTile(title: Text('重力旋转屏幕')),
              ],
            ),
          ),
        ),
      );

      expect(find.text('外观与显示'), findsOneWidget);
      expect(find.text('主题、旋转与取色'), findsOneWidget);
      expect(find.text('主题模式'), findsOneWidget);
      expect(find.text('重力旋转屏幕'), findsOneWidget);
      expect(find.byType(Divider), findsOneWidget);
    });

    testWidgets('AppPressable 提供点击与长按反馈', (tester) async {
      var taps = 0;
      var longPresses = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: Center(
              child: AppPressable(
                onTap: () => taps++,
                onLongPress: () => longPresses++,
                child: const SizedBox(
                  width: 120,
                  height: 48,
                  child: Center(child: Text('可点区域')),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('可点区域'));
      expect(taps, 1);
      await tester.longPress(find.text('可点区域'));
      expect(longPresses, 1);
    });
  });
}
