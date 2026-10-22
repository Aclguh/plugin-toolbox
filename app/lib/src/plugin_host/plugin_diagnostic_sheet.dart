import '../../l10n/app_localizations.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';
import 'package:plugin_toolbox_lua/plugin_toolbox_lua.dart';
import 'package:plugin_toolbox_ui/plugin_toolbox_ui.dart';

/// 插件运行期诊断与开发者控制台底部抽屉
class PluginDiagnosticSheet extends StatefulWidget {
  final DynamicPlugin plugin;
  final LuaPluginRunner? runner;
  final VoidCallback? onReload;

  const PluginDiagnosticSheet({
    super.key,
    required this.plugin,
    this.runner,
    this.onReload,
  });

  static Future<void> show(
    BuildContext context, {
    required DynamicPlugin plugin,
    LuaPluginRunner? runner,
    VoidCallback? onReload,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => PluginDiagnosticSheet(
        plugin: plugin,
        runner: runner,
        onReload: onReload,
      ),
    );
  }

  @override
  State<PluginDiagnosticSheet> createState() => _PluginDiagnosticSheetState();
}

class _PluginDiagnosticSheetState extends State<PluginDiagnosticSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  int _diskBytes = 0;
  bool _isLoadingDisk = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _refreshDiskUsage();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _refreshDiskUsage() async {
    final ctx = widget.plugin.context;
    if (ctx == null) {
      if (mounted) setState(() => _isLoadingDisk = false);
      return;
    }
    final bytes = await ctx.scanUsedBytes();
    if (mounted) {
      setState(() {
        _diskBytes = bytes;
        _isLoadingDisk = false;
      });
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final ctx = widget.plugin.context;
    final allocatedBytes = widget.runner?.engine.allocatedBytes ?? 0;
    final logs = ctx?.diagnosticLogs ?? const <String>[];

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // 标题栏：图标底衬 + 标题 + 关闭按钮
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.xs,
                AppSpacing.sm,
                AppSpacing.sm,
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      color: theme.colorScheme.primary.withValues(alpha: 0.12),
                    ),
                    child: Icon(
                      Icons.developer_mode_rounded,
                      color: theme.colorScheme.primary,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      l10n?.pluginDiagnosticsTitle ?? '插件诊断与控制台',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    tooltip: l10n?.close ?? '关闭',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            TabBar(
              controller: _tabController,
              tabs: [
                Tab(text: l10n?.tabStatus ?? '运行状态'),
                Tab(text: l10n?.tabLogs ?? '控制台日志'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Tab 1: 运行状态与资源配额
                  ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    children: [
                      _buildInfoCard(theme, ctx, allocatedBytes, l10n),
                      const SizedBox(height: AppSpacing.md),
                      _buildPermissionsCard(theme, ctx, l10n),
                      const SizedBox(height: AppSpacing.md),
                      _buildAuditTrailCard(theme, ctx, l10n),
                      const SizedBox(height: AppSpacing.md),
                      _buildActionsCard(theme, ctx, l10n),
                    ],
                  ),
                  // Tab 2: 控制台实时日志
                  Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg,
                          vertical: AppSpacing.sm,
                        ),
                        child: Row(
                          children: [
                            AppBadge(
                              label: l10n != null
                                  ? l10n.logCount(logs.length)
                                  : '共 ${logs.length} 条记录',
                              tone: AppBadgeTone.neutral,
                              dense: true,
                            ),
                            const Spacer(),
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                minimumSize: const Size(0, 36),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.sm,
                                ),
                              ),
                              icon: const Icon(Icons.copy_rounded, size: 16),
                              label: Text(l10n?.copyAll ?? '复制全部'),
                              onPressed: logs.isEmpty
                                  ? null
                                  : () {
                                      Clipboard.setData(ClipboardData(
                                        text: logs.join('\n'),
                                      ));
                                      AppSnack.success(
                                        context,
                                        l10n?.logsCopied ?? '已复制日志到剪贴板',
                                      );
                                    },
                            ),
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                minimumSize: const Size(0, 36),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.sm,
                                ),
                              ),
                              icon: const Icon(Icons.delete_outline, size: 16),
                              label: Text(l10n?.clear ?? '清空'),
                              onPressed: logs.isEmpty
                                  ? null
                                  : () {
                                      ctx?.clearDiagnosticLogs();
                                      setState(() {});
                                    },
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: logs.isEmpty
                            ? AppEmptyState(
                                icon: Icons.terminal_rounded,
                                title: l10n?.noLogsTitle ?? '暂无控制台日志输出',
                                message: l10n?.noLogsMessage ??
                                    '(Lua 中调用 print() 会在此处显示)',
                              )
                            : Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  AppSpacing.lg,
                                  0,
                                  AppSpacing.lg,
                                  AppSpacing.lg,
                                ),
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: theme
                                        .colorScheme.surfaceContainerLowest,
                                    borderRadius:
                                        BorderRadius.circular(AppRadius.md),
                                    border: Border.all(
                                      color: theme.colorScheme.outlineVariant
                                          .withValues(alpha: 0.5),
                                    ),
                                  ),
                                  child: ListView.builder(
                                    controller: scrollController,
                                    padding: const EdgeInsets.all(
                                      AppSpacing.md,
                                    ),
                                    itemCount: logs.length,
                                    itemBuilder: (context, index) {
                                      final line = logs[index];
                                      final isError = line.contains('[ERROR]');
                                      return Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 2,
                                        ),
                                        child: Text(
                                          line,
                                          style: TextStyle(
                                            fontFamily: AppTypography.monospace,
                                            fontSize: 12,
                                            height: 1.45,
                                            color: isError
                                                ? theme.colorScheme.error
                                                : theme.colorScheme.onSurface,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  /// 诊断分组的统一卡片外壳
  Widget _buildSection({
    required ThemeData theme,
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: theme.colorScheme.primary),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(
    ThemeData theme,
    PluginContext? ctx,
    int allocatedBytes,
    AppLocalizations? l10n,
  ) {
    return _buildSection(
      theme: theme,
      icon: Icons.memory_rounded,
      title: l10n?.basicInfoAndResources ?? '基础信息与资源占用',
      child: Column(
        children: [
          _buildRow(theme, l10n?.pluginId ?? '插件标识 (ID)', widget.plugin.id),
          _buildRow(
              theme, l10n?.version ?? '版本号', widget.plugin.manifest.version),
          _buildRow(theme, l10n?.category ?? '分类',
              widget.plugin.manifest.category.label),
          _buildRow(theme, l10n?.luaHeapAllocation ?? 'Lua 虚拟机堆分配',
              _formatBytes(allocatedBytes)),
          _buildRow(
            theme,
            l10n?.sandboxStorageUsage ?? '沙箱存储占用',
            _isLoadingDisk
                ? (l10n?.scanning ?? '扫描中...')
                : '${_formatBytes(_diskBytes)} / ${widget.plugin.manifest.storageQuotaMb} MB',
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionsCard(
    ThemeData theme,
    PluginContext? ctx,
    AppLocalizations? l10n,
  ) {
    final permissions = ctx?.grantedPermissions.toList() ?? [];
    return _buildSection(
      theme: theme,
      icon: Icons.verified_user_outlined,
      title: l10n?.grantedPermissionsTitle ?? '运行期已获授权',
      child: permissions.isEmpty
          ? Text(
              l10n?.noSensitivePermissions ?? '未授予任何敏感权限',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          : Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: permissions
                  .map(
                    (p) => AppBadge(
                      label: p.name,
                      tone: AppBadgeTone.primary,
                      dense: true,
                    ),
                  )
                  .toList(),
            ),
    );
  }

  Widget _buildAuditTrailCard(
    ThemeData theme,
    PluginContext? ctx,
    AppLocalizations? l10n,
  ) {
    final trail = ctx?.auditTrail ?? const <PermissionAuditRecord>[];
    return _buildSection(
      theme: theme,
      icon: Icons.security_rounded,
      title: l10n?.auditTrailTitle ?? '敏感权限访问审计',
      child: trail.isEmpty
          ? Text(
              l10n?.noAuditTrail ?? '暂无敏感权限访问记录',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          : Column(
              children: [
                for (final record in trail.reversed.take(10))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2.0),
                    child: Row(
                      children: [
                        AppBadge(
                          label: record.granted ? 'ALLOW' : 'DENY',
                          tone: record.granted
                              ? AppBadgeTone.success
                              : AppBadgeTone.danger,
                          dense: true,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          record.timestamp.toIso8601String().substring(11, 19),
                          style: TextStyle(
                            fontFamily: AppTypography.monospace,
                            fontSize: 11,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        AppBadge(
                          label: record.permission.name,
                          tone: AppBadgeTone.neutral,
                          dense: true,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            record.action,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildActionsCard(
    ThemeData theme,
    PluginContext? ctx,
    AppLocalizations? l10n,
  ) {
    return _buildSection(
      theme: theme,
      icon: Icons.handyman_outlined,
      title: l10n?.operationsAndDiagnostics ?? '运维与诊断操作',
      child: Column(
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.cleaning_services_outlined),
            title: Text(l10n?.cleanTempCache ?? '清理沙箱临时缓存'),
            subtitle: Text(
              l10n?.cleanTempCacheDesc ?? '安全清理 data/temp 目录下的非持久化缓存文件',
            ),
            onTap: () async {
              final root = widget.plugin.rootDir;
              final tempDir = Directory('${root.path}/data/temp');
              if (await tempDir.exists()) {
                await tempDir.delete(recursive: true);
              }
              ctx?.invalidateStorageQuotaCache();
              await _refreshDiskUsage();
              if (mounted) {
                AppSnack.success(
                  context,
                  l10n?.cleanedTempCacheSuccess ?? '已清理沙箱临时缓存',
                );
              }
            },
          ),
          if (widget.onReload != null)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.refresh_rounded),
              title: Text(l10n?.reloadPlugin ?? '重新加载插件'),
              subtitle: Text(
                l10n?.reloadPluginDesc ?? '重置 UI 状态与 Lua 运行时实例',
              ),
              onTap: () {
                Navigator.of(context).pop();
                widget.onReload?.call();
              },
            ),
        ],
      ),
    );
  }

  Widget _buildRow(ThemeData theme, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
