import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:plugin_toolbox_ui/plugin_toolbox_ui.dart';
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
          routerConfig: router,
        );
      },
    );
  }
}
