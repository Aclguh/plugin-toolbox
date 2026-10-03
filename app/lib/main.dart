import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'src/app.dart';
import 'src/providers/app_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  // 启动时统一初始化一次 SharedPreferences，经 Riverpod 注入各 Notifier，
  // 避免多处各自异步 getInstance 造成的冗余等待
  final prefs = await SharedPreferences.getInstance();
  runApp(
    UncontrolledProviderScope(
      container: ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      ),
      child: const PluginToolboxApp(),
    ),
  );
}
