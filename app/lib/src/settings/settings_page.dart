import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:plugin_toolbox_ui/plugin_toolbox_ui.dart';
import '../providers/app_providers.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final autoRotate = ref.watch(autoRotateProvider);

    return PluginPageScaffold(
      title: '设置',
      body: ListView(
        children: [
          const SectionHeader(title: '显示设置'),
          SwitchListTile(
            secondary: const Icon(Icons.screen_rotation_outlined),
            title: const Text('重力旋转屏幕'),
            subtitle: const Text('开启后允许横竖屏自由旋转，关闭时锁定竖屏'),
            value: autoRotate,
            onChanged: (val) {
              ref.read(autoRotateProvider.notifier).toggle(val);
            },
          ),
          const SectionHeader(title: '关于'),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('PluginToolbox'),
            subtitle: Text('版本 0.1.0 • 万物皆插件'),
          ),
        ],
      ),
    );
  }
}
