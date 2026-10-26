import '../../l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';
import 'package:plugin_toolbox_ui/plugin_toolbox_ui.dart';

import '../providers/app_providers.dart';

/// 运行时即时动态权限申请提示器 (Just-in-Time Permission Prompt)
class PluginPermissionPrompt {
  /// 提示用户授权敏感系统权限
  ///
  /// 若插件已具备该权限，直接返回 true；
  /// 若缺少权限，弹出规范 Material 3 解释与授权对话框；
  /// 用户同意后动态追加权限至 [PluginContext] 并持久化落盘。
  static Future<bool> requestPermission(
    BuildContext context, {
    required DynamicPlugin plugin,
    required PluginPermission permission,
    required WidgetRef ref,
    bool forcePrompt = false,
  }) async {
    final currentPermissions = plugin.context?.grantedPermissions ?? {};
    if (!forcePrompt && currentPermissions.contains(permission)) {
      return true;
    }

    final granted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final scheme = theme.colorScheme;
        final l10n = AppLocalizations.of(ctx);
        return AppDialog(
          icon: Icons.shield_outlined,
          title: l10n?.permissionPromptTitle ?? '权限申请提示',
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n != null
                    ? l10n.permissionPromptHeader(plugin.name)
                    : '插件「${plugin.name}」正在请求使用以下能力：',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(
                    color: scheme.primary.withValues(alpha: 0.28),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: scheme.primary.withValues(alpha: 0.12),
                      ),
                      child: Icon(
                        _getPermissionIcon(permission),
                        size: 20,
                        color: scheme.primary,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            permission.label,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: scheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xxs),
                          Text(
                            permission.description,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                l10n?.permissionPromptExplanation ?? '此操作需要向该插件授予对应权限。您是否同意授权？',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n?.deny ?? '拒绝'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l10n?.allow ?? '允许'),
            ),
          ],
        );
      },
    );

    if (granted == true) {
      final newPermissions = {...currentPermissions, permission};
      plugin.context?.grantPermission(permission);
      final registry = ref.read(pluginRegistryProvider);
      registry.setCustomPermissions(plugin.id, newPermissions);
      final registryNotifier = ref.read(pluginRegistryProvider.notifier);
      await registryNotifier.saveCustomPermissions(plugin.id, newPermissions);
      return true;
    }

    return false;
  }

  static IconData _getPermissionIcon(PluginPermission perm) {
    switch (perm) {
      case PluginPermission.camera:
        return Icons.camera_alt_outlined;
      case PluginPermission.photoLibrary:
        return Icons.photo_library_outlined;
      case PluginPermission.microphone:
        return Icons.mic_outlined;
      case PluginPermission.location:
        return Icons.location_on_outlined;
      case PluginPermission.bluetooth:
        return Icons.bluetooth_outlined;
      case PluginPermission.nfc:
        return Icons.nfc_outlined;
      case PluginPermission.storage:
        return Icons.folder_outlined;
      case PluginPermission.network:
        return Icons.public_outlined;
      case PluginPermission.clipboard:
        return Icons.content_paste_outlined;
      case PluginPermission.torch:
        return Icons.flash_on_outlined;
      case PluginPermission.sensor:
        return Icons.sensors_outlined;
      case PluginPermission.notification:
        return Icons.notifications_outlined;
      case PluginPermission.biometrics:
        return Icons.fingerprint_outlined;
      case PluginPermission.screen:
        return Icons.brightness_medium_outlined;
      case PluginPermission.ai:
        return Icons.psychology_outlined;
      case PluginPermission.database:
        return Icons.storage_outlined;
      case PluginPermission.ipc:
        return Icons.swap_horiz_outlined;
    }
  }
}
