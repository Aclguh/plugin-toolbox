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
    final securityMode = ref.watch(pluginSecurityModeProvider);

    return PluginPageScaffold(
      title: l10n?.settings ?? '设置',
      maxContentWidth: AppLayout.maxContentWidth,
      body: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
        children: [
          AppSection(
            title: l10n?.appearanceAndDisplay ?? '外观与显示',
            icon: Icons.palette_outlined,
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.screen_rotation_outlined),
                title: Text(l10n?.autoRotateScreen ?? '重力旋转屏幕'),
                subtitle: Text(
                  l10n?.autoRotateScreenDesc ?? '开启后允许横竖屏自由旋转，关闭时锁定竖屏',
                ),
                value: autoRotate,
                onChanged: (val) {
                  ref.read(autoRotateProvider.notifier).toggle(val);
                },
              ),
              ListTile(
                leading: const Icon(Icons.brightness_6_outlined),
                title: Text(l10n?.themeMode ?? '主题模式'),
                subtitle: Text(switch (themeMode) {
                  ThemeMode.dark => l10n?.themeDark ?? '品牌深色（默认）',
                  ThemeMode.light => l10n?.themeLight ?? '清新浅色',
                  ThemeMode.system => l10n?.themeSystem ?? '跟随系统',
                }),
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: () => _showThemeModeSheet(context, ref, themeMode),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.color_lens_outlined),
                title: Text(l10n?.dynamicColor ?? '动态取色 (Material You)'),
                subtitle: Text(
                  l10n?.dynamicColorDesc ?? '开启后提取壁纸色彩，关闭时使用工具箱专属品牌配色',
                ),
                value: useDynamicColor,
                onChanged: (val) {
                  ref.read(dynamicColorEnabledProvider.notifier).toggle(val);
                },
              ),
            ],
          ),
          AppSection(
            title: '插件与仓库',
            icon: Icons.inventory_2_outlined,
            subtitle: '插件目录的来源配置，影响商店可安装的插件集合',
            children: [
              ListTile(
                leading: const Icon(Icons.source_outlined),
                title: const Text('自定义插件仓库'),
                subtitle: Text(
                  repoConfig.isDefault
                      ? '当前: Aclguh/PTX-plugins（官方默认）'
                      : '当前: ${repoConfig.summary}',
                ),
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: () => _showCustomRepoDialog(context, ref, repoConfig),
              ),
              ListTile(
                leading: const Icon(Icons.verified_user_outlined),
                title: const Text('插件安全策略'),
                subtitle: Text(
                  switch (securityMode) {
                    PluginSecurityMode.strict => '严格安全模式（仅允许安装受信任签名插件）',
                    PluginSecurityMode.developer => '开发者模式（放行所有未签名插件）',
                    PluginSecurityMode.warning => '安全警示模式（未签名插件弹窗提醒，默认）',
                  },
                ),
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: () =>
                    _showSecurityModeDialog(context, ref, securityMode),
              ),
            ],
          ),
          AppSection(
            title: l10n?.about ?? '关于',
            icon: Icons.info_outline_rounded,
            children: [
              ListTile(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: Image.asset(
                    'assets/icons/plugin-toolbox-icon.png',
                    width: 36,
                    height: 36,
                  ),
                ),
                title: const Text('PluginToolbox'),
                subtitle: const Text('版本 0.2.1 • 万物皆插件'),
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: () => _showAboutDetailsDialog(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showSecurityModeDialog(
    BuildContext context,
    WidgetRef ref,
    PluginSecurityMode currentMode,
  ) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return AppDialog(
          icon: Icons.shield_outlined,
          title: '插件安全策略',
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final mode in PluginSecurityMode.values)
                ListTile(
                  leading: Icon(
                    mode == currentMode
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: mode == currentMode
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  title: Text(switch (mode) {
                    PluginSecurityMode.warning => '安全警示模式（默认）',
                    PluginSecurityMode.strict => '严格安全模式',
                    PluginSecurityMode.developer => '开发者模式',
                  }),
                  subtitle: Text(switch (mode) {
                    PluginSecurityMode.warning => '安装未签名插件时弹出安全确认，拦截被篡改的安装包',
                    PluginSecurityMode.strict =>
                      '仅允许安装包含合法 Ed25519 数字签名的插件，杜绝未知来源代码',
                    PluginSecurityMode.developer => '放行所有本地开发与未签名插件，仅拦截被篡改的损坏包',
                  }),
                  onTap: () {
                    ref.read(pluginSecurityModeProvider.notifier).setMode(mode);
                    Navigator.pop(ctx);
                  },
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
          ],
        );
      },
    );
  }

  /// 复制文本到剪贴板并弹出轻量提示
  static void _copyText(BuildContext context, String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    AppSnack.success(context, '$label已复制到剪贴板');
  }

  /// 主题模式选择面板：以底部抽屉替代下拉框，
  /// 移动端单手可达，且能完整展示"当前选中"状态。
  void _showThemeModeSheet(
    BuildContext context,
    WidgetRef ref,
    ThemeMode current,
  ) {
    final l10n = AppLocalizations.of(context);
    final options = <(ThemeMode, String, IconData)>[
      (ThemeMode.dark, l10n?.themeDark ?? '品牌深色（默认）', Icons.dark_mode_outlined),
      (ThemeMode.light, l10n?.themeLight ?? '清新浅色', Icons.light_mode_outlined),
      (
        ThemeMode.system,
        l10n?.themeSystem ?? '跟随系统',
        Icons.brightness_auto_outlined
      ),
    ];

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.xs,
                  AppSpacing.lg,
                  AppSpacing.md,
                ),
                child: Text(
                  l10n?.themeMode ?? '主题模式',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              for (final option in options)
                ListTile(
                  leading: Icon(
                    option.$3,
                    color: option.$1 == current
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  title: Text(option.$2),
                  trailing: option.$1 == current
                      ? Icon(
                          Icons.check_circle_rounded,
                          color: theme.colorScheme.primary,
                          size: 20,
                        )
                      : null,
                  onTap: () {
                    ref.read(themeModeProvider.notifier).setMode(option.$1);
                    Navigator.of(ctx).pop();
                  },
                ),
              const SizedBox(height: AppSpacing.md),
            ],
          ),
        );
      },
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
        builder: (ctx, setState) => AppDialog(
          icon: Icons.cloud_sync_outlined,
          title: '自定义插件仓库',
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '支持输入 GitHub 仓库链接或 owner/repo 格式。'
                '保存后插件商店将从该仓库拉取插件目录与安装包。',
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                controller: controller,
                autofocus: true,
                textInputAction: TextInputAction.done,
                decoration: InputDecoration(
                  labelText: 'GitHub 仓库链接',
                  hintText: '例如: https://github.com/owner/repo',
                  errorText: errorText,
                  prefixIcon: const Icon(Icons.link_rounded, size: 20),
                  suffixIcon: controller.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          tooltip: '清空输入',
                          onPressed: () {
                            setState(() {
                              controller.clear();
                              errorText = null;
                            });
                          },
                        )
                      : null,
                ),
                onChanged: (_) => setState(() => errorText = null),
              ),
              const SizedBox(height: AppSpacing.md),
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
                const SizedBox(height: AppSpacing.lg),
                Text(
                  '已订阅的源 (点击快速选择):',
                  style: Theme.of(ctx).textTheme.labelMedium,
                ),
                const SizedBox(height: AppSpacing.xs),
                Card(
                  margin: EdgeInsets.zero,
                  child: Column(
                    children: [
                      for (final cfg in ref
                          .read(customPluginRepositoryProvider.notifier)
                          .savedConfigs)
                        ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.only(
                            left: AppSpacing.md,
                            right: AppSpacing.xs,
                          ),
                          leading: Icon(
                            cfg.summary.toLowerCase() ==
                                    currentConfig.summary.toLowerCase()
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                            size: 18,
                            color: cfg.summary.toLowerCase() ==
                                    currentConfig.summary.toLowerCase()
                                ? Theme.of(ctx).colorScheme.primary
                                : Theme.of(ctx).colorScheme.outline,
                          ),
                          title: Text(
                            cfg.summary + (cfg.isDefault ? ' (官方默认)' : ''),
                            style: Theme.of(ctx).textTheme.bodyMedium,
                          ),
                          trailing: !cfg.isDefault
                              ? IconButton(
                                  icon: const Icon(Icons.close, size: 16),
                                  tooltip: '移除该源',
                                  onPressed: () async {
                                    await ref
                                        .read(customPluginRepositoryProvider
                                            .notifier)
                                        .removeSavedRepository(cfg);
                                    setState(() {});
                                  },
                                )
                              : null,
                          onTap: () {
                            controller.text =
                                cfg.isDefault ? '' : cfg.githubUrl;
                            setState(() => errorText = null);
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ],
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
                    AppSnack.info(context, '已恢复为官方默认插件仓库');
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
                    AppSnack.info(context, '已恢复为官方默认插件仓库');
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
                  AppSnack.success(context, '插件仓库已切换为: ${parsed.summary}');
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
        titlePadding: const EdgeInsets.fromLTRB(
          AppSpacing.xxl,
          AppSpacing.xxl,
          AppSpacing.xxl,
          AppSpacing.md,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
        actionsPadding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.lg,
        ),
        title: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.xs),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.xl),
                border: Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.25),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                child: Image.asset(
                  'assets/icons/plugin-toolbox-icon.png',
                  width: 56,
                  height: 56,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'PluginToolbox',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 20,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              '版本 0.2.1 (Build 3)',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
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
          child: Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              child: Column(
                children: [
                  _buildInfoRow(
                    context: ctx,
                    icon: Icons.android_outlined,
                    title: '应用包名',
                    value: kAppPackageName,
                    copyable: true,
                    onCopy: () => _copyText(ctx, kAppPackageName, '应用包名'),
                  ),
                  const Divider(height: 1),
                  _buildInfoRow(
                    context: ctx,
                    icon: Icons.code_outlined,
                    title: 'GitHub 仓库',
                    value: kAppOfficialRepository,
                    copyable: true,
                    onCopy: () => _copyText(
                      ctx,
                      kAppOfficialRepository,
                      'GitHub 仓库链接',
                    ),
                  ),
                  const Divider(height: 1),
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
                  const Divider(height: 1),
                  _buildInfoRow(
                    context: ctx,
                    icon: Icons.layers_outlined,
                    title: '核心架构',
                    value: kAppArchitecture,
                    copyable: false,
                  ),
                  const Divider(height: 1),
                  _buildInfoRow(
                    context: ctx,
                    icon: Icons.group_outlined,
                    title: '开发团队',
                    value: kAppTeam,
                    copyable: false,
                  ),
                ],
              ),
            ),
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
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                color: theme.colorScheme.primary.withValues(alpha: 0.12),
              ),
              child: Icon(icon, size: 17, color: theme.colorScheme.primary),
            ),
            const SizedBox(width: AppSpacing.md),
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
                  const SizedBox(height: AppSpacing.xxs),
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
                icon: const Icon(Icons.copy_outlined, size: 17),
                tooltip: '复制 $title',
                visualDensity: VisualDensity.compact,
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
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return AppDialog(
          icon: Icons.gavel_outlined,
          title: '开源协议 (MIT License)',
          scrollable: false,
          content: SizedBox(
            width: double.maxFinite,
            child: Container(
              constraints: const BoxConstraints(maxHeight: 320),
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                  color:
                      theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: const SingleChildScrollView(
                child: SelectableText(
                  kAppFullLicenseText,
                  style: TextStyle(
                    fontFamily: AppTypography.monospace,
                    fontSize: 12,
                    height: 1.5,
                  ),
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
        );
      },
    );
  }
}
