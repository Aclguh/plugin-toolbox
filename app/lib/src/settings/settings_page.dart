import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';
import 'package:plugin_toolbox_ui/plugin_toolbox_ui.dart';

import '../../l10n/app_localizations.dart';
import '../plugin_store/store_providers.dart';
import '../providers/app_providers.dart';

/// 软件元数据常量
const String kAppPackageName = 'com.plugintoolbox.plugin_toolbox';
const String kAppOfficialRepository =
    'https://github.com/Aclguh/plugin-toolbox';
const String kAppLicenseName = 'MIT License';
const String kAppTeam = 'PluginToolbox Team (Aclguh)';
const String kAppArchitecture = 'Flutter / Pure Dart Core / Lua 5.1 / DUI AST';

/// 完整开源协议文本
const String kAppFullLicenseText = '''MIT License

Copyright (c) 2026 PluginToolbox contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.''';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final autoRotate = ref.watch(autoRotateProvider);
    final themeMode = ref.watch(themeModeProvider);
    final useDynamicColor = ref.watch(dynamicColorEnabledProvider);
    final repoConfig = ref.watch(customPluginRepositoryProvider);

    return PluginPageScaffold(
      title: l10n?.settings ?? '设置',
      body: ListView(
        children: [
          SectionHeader(title: l10n?.appearanceAndDisplay ?? '外观与显示'),
          SwitchListTile(
            secondary: const Icon(Icons.screen_rotation_outlined),
            title: Text(l10n?.autoRotateScreen ?? '重力旋转屏幕'),
            subtitle:
                Text(l10n?.autoRotateScreenDesc ?? '开启后允许横竖屏自由旋转，关闭时锁定竖屏'),
            value: autoRotate,
            onChanged: (val) {
              ref.read(autoRotateProvider.notifier).toggle(val);
            },
          ),
          ListTile(
            leading: const Icon(Icons.palette_outlined),
            title: Text(l10n?.themeMode ?? '主题模式'),
            subtitle: Text(switch (themeMode) {
              ThemeMode.dark => l10n?.themeDark ?? '品牌深色（默认）',
              ThemeMode.light => l10n?.themeLight ?? '清新浅色',
              ThemeMode.system => l10n?.themeSystem ?? '跟随系统',
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
            title: Text(l10n?.dynamicColor ?? '动态取色 (Material You)'),
            subtitle:
                Text(l10n?.dynamicColorDesc ?? '开启后提取壁纸色彩，关闭时使用工具箱专属品牌配色'),
            value: useDynamicColor,
            onChanged: (val) {
              ref.read(dynamicColorEnabledProvider.notifier).toggle(val);
            },
          ),
          const SectionHeader(title: '插件与仓库'),
          ListTile(
            leading: const Icon(Icons.source_outlined),
            title: const Text('自定义插件仓库'),
            subtitle: Text(
              repoConfig.isDefault
                  ? '当前: Aclguh/PTX-plugins（官方默认）'
                  : '当前: ${repoConfig.summary}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showCustomRepoDialog(context, ref, repoConfig),
          ),
          SectionHeader(title: l10n?.about ?? '关于'),
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
            subtitle: const Text('版本 0.2.1 • 万物皆插件'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showAboutDetailsDialog(context),
          ),
        ],
      ),
    );
  }

  /// 复制文本到剪贴板并弹出轻量提示
  static void _copyText(BuildContext context, String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label已复制到剪贴板'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// 弹出自定义插件仓库配置对话框
  void _showCustomRepoDialog(
    BuildContext context,
    WidgetRef ref,
    PluginRepositoryConfig currentConfig,
  ) {
    final controller = TextEditingController(
      text: currentConfig.isDefault
          ? ''
          : (currentConfig.customUrl ?? currentConfig.githubUrl),
    );
    String? errorText;

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('自定义插件仓库'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '支持输入 GitHub 仓库链接或 owner/repo 格式。'
                  '保存后插件商店将从该仓库拉取插件目录与安装包。',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'GitHub 仓库链接',
                    hintText: '例如: https://github.com/owner/repo',
                    errorText: errorText,
                    border: const OutlineInputBorder(),
                    suffixIcon: controller.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 20),
                            onPressed: () {
                              setState(() {
                                controller.clear();
                                errorText = null;
                              });
                            },
                          )
                        : null,
                  ),
                  onChanged: (_) {
                    if (errorText != null) {
                      setState(() => errorText = null);
                    }
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  '当前仓库: ${currentConfig.summary}${currentConfig.isDefault ? '（官方默认）' : ''}',
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                      ),
                ),
                if (ref
                        .read(customPluginRepositoryProvider.notifier)
                        .savedConfigs
                        .length >
                    1) ...[
                  const SizedBox(height: 12),
                  const Divider(),
                  const Text('已订阅的源 (点击快速选择):',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 4),
                  for (final cfg in ref
                      .read(customPluginRepositoryProvider.notifier)
                      .savedConfigs)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        cfg.summary.toLowerCase() ==
                                currentConfig.summary.toLowerCase()
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        size: 18,
                        color: cfg.summary.toLowerCase() ==
                                currentConfig.summary.toLowerCase()
                            ? Theme.of(ctx).colorScheme.primary
                            : null,
                      ),
                      title: Text(
                        cfg.summary + (cfg.isDefault ? ' (官方默认)' : ''),
                        style: const TextStyle(fontSize: 13),
                      ),
                      trailing: !cfg.isDefault
                          ? IconButton(
                              icon: const Icon(Icons.close, size: 16),
                              tooltip: '移除该源',
                              onPressed: () async {
                                await ref
                                    .read(
                                        customPluginRepositoryProvider.notifier)
                                    .removeSavedRepository(cfg);
                                setState(() {});
                              },
                            )
                          : null,
                      onTap: () {
                        controller.text = cfg.isDefault ? '' : cfg.githubUrl;
                        setState(() => errorText = null);
                      },
                    ),
                ],
              ],
            ),
          ),
          actions: [
            if (!currentConfig.isDefault)
              TextButton(
                onPressed: () async {
                  await ref
                      .read(customPluginRepositoryProvider.notifier)
                      .resetToDefault();
                  ref.invalidate(pluginStoreResolvedRefProvider);
                  ref.invalidate(pluginStoreCatalogProvider);
                  if (ctx.mounted) Navigator.of(ctx).pop();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('已恢复为官方默认插件仓库'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                },
                child: const Text('恢复默认'),
              ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                final text = controller.text.trim();
                if (text.isEmpty) {
                  await ref
                      .read(customPluginRepositoryProvider.notifier)
                      .resetToDefault();
                  ref.invalidate(pluginStoreResolvedRefProvider);
                  ref.invalidate(pluginStoreCatalogProvider);
                  if (ctx.mounted) Navigator.of(ctx).pop();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('已恢复为官方默认插件仓库'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                  return;
                }

                final parsed = PluginRepositoryConfig.tryParse(text);
                if (parsed == null) {
                  setState(() {
                    errorText = '请输入有效的 GitHub 仓库链接，例如：owner/repo';
                  });
                  return;
                }

                final success = await ref
                    .read(customPluginRepositoryProvider.notifier)
                    .setRepository(text);
                if (!success) {
                  setState(() {
                    errorText = '仓库链接格式无效';
                  });
                  return;
                }

                ref.invalidate(pluginStoreResolvedRefProvider);
                ref.invalidate(pluginStoreCatalogProvider);

                if (ctx.mounted) Navigator.of(ctx).pop();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('插件仓库已切换为: ${parsed.summary}'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  /// 弹出全量软件信息关于对话框
  void _showAboutDetailsDialog(BuildContext context) {
    final theme = Theme.of(context);

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
        contentPadding: const EdgeInsets.symmetric(horizontal: 24),
        actionsPadding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        title: Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset(
                'assets/icons/plugin-toolbox-icon.png',
                width: 56,
                height: 56,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'PluginToolbox',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
            ),
            const SizedBox(height: 4),
            Text(
              '版本 0.2.1 (Build 3)',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '万物皆插件 • 极致轻量的动态插件化工具箱',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              _buildInfoRow(
                context: ctx,
                icon: Icons.android_outlined,
                title: '应用包名',
                value: kAppPackageName,
                copyable: true,
                onCopy: () => _copyText(ctx, kAppPackageName, '应用包名'),
              ),
              const Divider(height: 16),
              _buildInfoRow(
                context: ctx,
                icon: Icons.code_outlined,
                title: 'GitHub 仓库',
                value: kAppOfficialRepository,
                copyable: true,
                onCopy: () =>
                    _copyText(ctx, kAppOfficialRepository, 'GitHub 仓库链接'),
              ),
              const Divider(height: 16),
              _buildInfoRow(
                context: ctx,
                icon: Icons.gavel_outlined,
                title: '开源许可',
                value: kAppLicenseName,
                copyable: false,
                trailing: TextButton(
                  onPressed: () => _showLicenseDialog(ctx),
                  child: const Text('查看协议'),
                ),
              ),
              const Divider(height: 16),
              _buildInfoRow(
                context: ctx,
                icon: Icons.layers_outlined,
                title: '核心架构',
                value: kAppArchitecture,
                copyable: false,
              ),
              const Divider(height: 16),
              _buildInfoRow(
                context: ctx,
                icon: Icons.group_outlined,
                title: '开发团队',
                value: kAppTeam,
                copyable: false,
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => _showLicenseDialog(ctx),
            child: const Text('开源协议'),
          ),
          FilledButton.tonal(
            onPressed: () {
              const allInfo = '''应用名称: PluginToolbox
版本: 0.2.1 (Build 3)
包名: $kAppPackageName
GitHub 仓库: $kAppOfficialRepository
开源许可: $kAppLicenseName
核心架构: $kAppArchitecture
开发团队: $kAppTeam''';
              _copyText(ctx, allInfo, '全部软件信息');
            },
            child: const Text('复制信息'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  /// 构建单行信息组件
  Widget _buildInfoRow({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String value,
    required bool copyable,
    VoidCallback? onCopy,
    Widget? trailing,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: copyable ? onCopy : null,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              size: 20,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null)
              trailing
            else if (copyable)
              IconButton(
                icon: const Icon(Icons.copy_outlined, size: 18),
                tooltip: '复制 $title',
                onPressed: onCopy,
              ),
          ],
        ),
      ),
    );
  }

  /// 弹出完整开源协议对话框
  void _showLicenseDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('开源协议 (MIT License)'),
        content: const SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(
              kAppFullLicenseText,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ),
        actions: [
          FilledButton.tonal(
            onPressed: () => _copyText(ctx, kAppFullLicenseText, '开源协议全文'),
            child: const Text('复制协议'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}
