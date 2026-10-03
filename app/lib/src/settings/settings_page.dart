import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:plugin_toolbox_ui/plugin_toolbox_ui.dart';
import '../providers/app_providers.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final autoRotate = ref.watch(autoRotateProvider);
    final themeMode = ref.watch(themeModeProvider);
    final useDynamicColor = ref.watch(dynamicColorEnabledProvider);

    return PluginPageScaffold(
      title: '设置',
      body: ListView(
        children: [
          const SectionHeader(title: '外观与显示'),
          SwitchListTile(
            secondary: const Icon(Icons.screen_rotation_outlined),
            title: const Text('重力旋转屏幕'),
            subtitle: const Text('开启后允许横竖屏自由旋转，关闭时锁定竖屏'),
            value: autoRotate,
            onChanged: (val) {
              ref.read(autoRotateProvider.notifier).toggle(val);
            },
          ),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: const Text('主题模式'),
            subtitle: Text(switch (themeMode) {
              ThemeMode.dark => '品牌深色（默认）',
              ThemeMode.light => '清新浅色',
              ThemeMode.system => '跟随系统',
            }),
            trailing: DropdownButton<ThemeMode>(
              value: themeMode,
              underline: const SizedBox(),
              items: const [
                DropdownMenuItem(
                  value: ThemeMode.dark,
                  child: Text('品牌深色'),
                ),
                DropdownMenuItem(
                  value: ThemeMode.light,
                  child: Text('清新浅色'),
                ),
                DropdownMenuItem(
                  value: ThemeMode.system,
                  child: Text('跟随系统'),
                ),
              ],
              onChanged: (mode) {
                if (mode != null) {
                  ref.read(themeModeProvider.notifier).setMode(mode);
                }
              },
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.color_lens_outlined),
            title: const Text('动态取色 (Material You)'),
            subtitle: const Text('开启后提取壁纸色彩，关闭时使用工具箱专属品牌配色'),
            value: useDynamicColor,
            onChanged: (val) {
              ref.read(dynamicColorEnabledProvider.notifier).toggle(val);
            },
          ),
          const SectionHeader(title: '关于'),
          ListTile(
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'assets/icons/plugin-toolbox-icon.png',
                width: 36,
                height: 36,
              ),
            ),
            title: const Text('PluginToolbox'),
            subtitle: const Text('版本 0.1.0 • 万物皆插件'),
          ),
        ],
      ),
    );
  }
}
