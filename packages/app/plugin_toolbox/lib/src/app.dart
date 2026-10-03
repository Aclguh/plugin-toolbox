import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:plugin_toolbox_ui/plugin_toolbox_ui.dart';
import 'router/app_router.dart';

class PluginToolboxApp extends ConsumerWidget {
  const PluginToolboxApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        return MaterialApp.router(
          title: 'PluginToolbox',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(dynamicColorScheme: lightDynamic),
          darkTheme: AppTheme.dark(dynamicColorScheme: darkDynamic),
          themeMode: ThemeMode.system,
          routerConfig: router,
        );
      },
    );
  }
}
