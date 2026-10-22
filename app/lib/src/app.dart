import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:plugin_toolbox_ui/plugin_toolbox_ui.dart';
import '../l10n/app_localizations.dart';
import 'providers/app_providers.dart';
import 'router/app_router.dart';

class PluginToolboxApp extends ConsumerWidget {
  const PluginToolboxApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final themeMode = ref.watch(themeModeProvider);
    final useDynamicColor = ref.watch(dynamicColorEnabledProvider);

    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        final lightScheme = useDynamicColor ? lightDynamic : null;
        final darkScheme = useDynamicColor ? darkDynamic : null;

        return MaterialApp.router(
          title: 'PluginToolbox',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(dynamicColorScheme: lightScheme),
          darkTheme: AppTheme.dark(dynamicColorScheme: darkScheme),
          themeMode: themeMode,
          // 主题切换采用统一缓动，避免瞬间闪变造成的割裂感
          themeAnimationDuration: AppMotion.normal,
          themeAnimationCurve: AppMotion.emphasized,
          routerConfig: router,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        );
      },
    );
  }
}
