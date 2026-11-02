import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:plugin_toolbox_ui/plugin_toolbox_ui.dart';

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

/// 全量软件信息「关于」对话框
class AboutDetailsDialog extends StatelessWidget {
  const AboutDetailsDialog({super.key});

  /// 弹出全量软件信息关于对话框
  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => const AboutDetailsDialog(),
    );
  }

  static void _copyText(BuildContext context, String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    AppSnack.success(context, '$label已复制到剪贴板');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
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
                  context: context,
                  icon: Icons.android_outlined,
                  title: '应用包名',
                  value: kAppPackageName,
                  copyable: true,
                  onCopy: () => _copyText(context, kAppPackageName, '应用包名'),
                ),
                const Divider(height: 1),
                _buildInfoRow(
                  context: context,
                  icon: Icons.code_outlined,
                  title: 'GitHub 仓库',
                  value: kAppOfficialRepository,
                  copyable: true,
                  onCopy: () => _copyText(
                    context,
                    kAppOfficialRepository,
                    'GitHub 仓库链接',
                  ),
                ),
                const Divider(height: 1),
                _buildInfoRow(
                  context: context,
                  icon: Icons.gavel_outlined,
                  title: '开源许可',
                  value: kAppLicenseName,
                  copyable: false,
                  trailing: TextButton(
                    onPressed: () => LicenseDialog.show(context),
                    child: const Text('查看协议'),
                  ),
                ),
                const Divider(height: 1),
                _buildInfoRow(
                  context: context,
                  icon: Icons.layers_outlined,
                  title: '核心架构',
                  value: kAppArchitecture,
                  copyable: false,
                ),
                const Divider(height: 1),
                _buildInfoRow(
                  context: context,
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
          onPressed: () => LicenseDialog.show(context),
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
            _copyText(context, allInfo, '全部软件信息');
          },
          child: const Text('复制信息'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
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
}

/// 弹出完整开源协议对话框
class LicenseDialog extends StatelessWidget {
  const LicenseDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => const LicenseDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: const SingleChildScrollView(
            child: SelectableText(
              kAppFullLicenseText,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                height: 1.45,
              ),
            ),
          ),
        ),
      ),
      actions: [
        FilledButton.tonal(
          onPressed: () {
            Clipboard.setData(const ClipboardData(text: kAppFullLicenseText));
            AppSnack.success(context, '开源协议全文已复制到剪贴板');
          },
          child: const Text('复制协议'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}
