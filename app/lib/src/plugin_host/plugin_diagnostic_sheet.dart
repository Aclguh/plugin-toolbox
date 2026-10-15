import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';
import 'package:plugin_toolbox_lua/plugin_toolbox_lua.dart';

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
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
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
            // 顶端拖拽提手与标题栏
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 8),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurfaceVariant.withAlpha(80),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Icon(
                    Icons.developer_mode_rounded,
                    color: theme.colorScheme.primary,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '插件诊断与控制台',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            TabBar(
              controller: _tabController,
              labelColor: theme.colorScheme.primary,
              unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
              indicatorColor: theme.colorScheme.primary,
              tabs: const [
                Tab(text: '运行状态'),
                Tab(text: '控制台日志'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Tab 1: 运行状态与资源配额
                  ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.all(16),
                    children: [
                      _buildInfoCard(theme, ctx, allocatedBytes),
                      const SizedBox(height: 16),
                      _buildPermissionsCard(theme, ctx),
                      const SizedBox(height: 16),
                      _buildActionsCard(theme, ctx),
                    ],
                  ),
                  // Tab 2: 控制台实时日志
                  Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: Row(
                          children: [
                            Text(
                              '共 ${logs.length} 条记录',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const Spacer(),
                            TextButton.icon(
                              icon: const Icon(Icons.copy_rounded, size: 16),
                              label: const Text('复制全部'),
                              onPressed: logs.isEmpty
                                  ? null
                                  : () {
                                      Clipboard.setData(ClipboardData(
                                        text: logs.join('\n'),
                                      ));
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                          content: Text('已复制日志到剪贴板'),
                                          duration: Duration(seconds: 1),
                                        ),
                                      );
                                    },
                            ),
                            TextButton.icon(
                              icon: const Icon(Icons.delete_outline, size: 16),
                              label: const Text('清空'),
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
                      const Divider(height: 1),
                      Expanded(
                        child: logs.isEmpty
                            ? Center(
                                child: Text(
                                  '暂无控制台日志输出\n(Lua 中调用 print() 会在此处显示)',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              )
                            : ListView.builder(
                                controller: scrollController,
                                padding: const EdgeInsets.all(12),
                                itemCount: logs.length,
                                itemBuilder: (context, index) {
                                  final line = logs[index];
                                  final isError = line.contains('[ERROR]');
                                  return Padding(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 2),
                                    child: Text(
                                      line,
                                      style: TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 12,
                                        color: isError
                                            ? theme.colorScheme.error
                                            : theme.colorScheme.onSurface,
                                      ),
                                    ),
                                  );
                                },
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

  Widget _buildInfoCard(
    ThemeData theme,
    PluginContext? ctx,
    int allocatedBytes,
  ) {
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withAlpha(80),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '基础信息与资源占用',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            _buildRow('插件标识 (ID)', widget.plugin.id),
            _buildRow('版本号', widget.plugin.manifest.version),
            _buildRow('分类', widget.plugin.manifest.category.label),
            _buildRow(
              'Lua 虚拟机堆分配',
              _formatBytes(allocatedBytes),
            ),
            _buildRow(
              '沙箱存储占用',
              _isLoadingDisk
                  ? '扫描中...'
                  : '${_formatBytes(_diskBytes)} / ${widget.plugin.manifest.storageQuotaMb} MB',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionsCard(ThemeData theme, PluginContext? ctx) {
    final permissions = ctx?.grantedPermissions.toList() ?? [];
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withAlpha(80),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '运行期已获授权',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            if (permissions.isEmpty)
              Text(
                '未授予任何敏感权限',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: permissions.map((p) {
                  return Chip(
                    label: Text(p.name),
                    visualDensity: VisualDensity.compact,
                    backgroundColor:
                        theme.colorScheme.primaryContainer.withAlpha(120),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionsCard(ThemeData theme, PluginContext? ctx) {
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withAlpha(80),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '运维与诊断操作',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.cleaning_services_outlined),
              title: const Text('清理沙箱临时缓存'),
              subtitle: const Text('安全清理 data/temp 目录下的非持久化缓存文件'),
              onTap: () async {
                final root = widget.plugin.rootDir;
                final tempDir = Directory('${root.path}/data/temp');
                if (await tempDir.exists()) {
                  await tempDir.delete(recursive: true);
                }
                ctx?.invalidateStorageQuotaCache();
                await _refreshDiskUsage();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已清理沙箱临时缓存')),
                  );
                }
              },
            ),
            if (widget.onReload != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.refresh_rounded),
                title: const Text('重新加载插件'),
                subtitle: const Text('重置 UI 状态与 Lua 运行时实例'),
                onTap: () {
                  Navigator.of(context).pop();
                  widget.onReload?.call();
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13)),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
