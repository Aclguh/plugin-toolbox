import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_toolbox/src/providers/app_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ThemeModeNotifier 状态转换', () {
    test('默认品牌深色，切换后实时生效并持久化', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final notifier = ThemeModeNotifier(prefs);
      expect(notifier.state, ThemeMode.dark);

      await notifier.setMode(ThemeMode.light);
      expect(notifier.state, ThemeMode.light);
      expect(prefs.getString('app_theme_mode'), 'light');

      await notifier.setMode(ThemeMode.system);
      expect(notifier.state, ThemeMode.system);
      expect(prefs.getString('app_theme_mode'), 'system');
    });

    test('重新构造时从持久化恢复上次主题模式', () async {
      SharedPreferences.setMockInitialValues({'app_theme_mode': 'light'});
      final prefs = await SharedPreferences.getInstance();
      final notifier = ThemeModeNotifier(prefs);
      expect(notifier.state, ThemeMode.light);
    });

    test('持久化值损坏时安全降级为默认品牌深色', () async {
      SharedPreferences.setMockInitialValues({'app_theme_mode': 123});
      final prefs = await SharedPreferences.getInstance();
      final notifier = ThemeModeNotifier(prefs);
      expect(notifier.state, ThemeMode.dark);
    });
  });

  group('OrientationNotifier 状态转换', () {
    test('默认锁定竖屏，开关切换并持久化', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final notifier = OrientationNotifier(prefs);
      expect(notifier.state, isFalse);

      await notifier.toggle(true);
      expect(notifier.state, isTrue);
      expect(prefs.getBool('auto_rotate_screen'), isTrue);

      await notifier.toggle(false);
      expect(notifier.state, isFalse);
      expect(prefs.getBool('auto_rotate_screen'), isFalse);
    });

    test('初始状态从持久化载入', () async {
      SharedPreferences.setMockInitialValues({'auto_rotate_screen': true});
      final prefs = await SharedPreferences.getInstance();
      final notifier = OrientationNotifier(prefs);
      expect(notifier.state, isTrue);
    });

    test('持久化值类型损坏时安全降级为锁定竖屏', () async {
      SharedPreferences.setMockInitialValues({'auto_rotate_screen': 'broken'});
      final prefs = await SharedPreferences.getInstance();
      final notifier = OrientationNotifier(prefs);
      expect(notifier.state, isFalse);
    });
  });

  group('DynamicColorNotifier 状态转换', () {
    test('动态取色默认关闭，切换并持久化', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final notifier = DynamicColorNotifier(prefs);
      expect(notifier.state, isFalse);

      await notifier.toggle(true);
      expect(notifier.state, isTrue);
      expect(prefs.getBool('use_dynamic_color'), isTrue);
    });
  });
}
