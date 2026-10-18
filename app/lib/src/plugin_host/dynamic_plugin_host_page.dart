import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';
import 'package:plugin_toolbox_ui/plugin_toolbox_ui.dart';

import '../providers/app_providers.dart';
import 'desktop_simulation_adapter.dart';
import 'plugin_dialog_service.dart';
import 'plugin_diagnostic_sheet.dart';
import 'plugin_host_session.dart';
import 'plugin_permission_prompt.dart';

/// 动态插件宿主页面容器
class DynamicPluginHostPage extends ConsumerStatefulWidget {
  final DynamicPlugin plugin;

  /// 跨插件调起（plugin.open）携带的初始参数，经路由 extra 贯通至此
  final Map<String, dynamic>? initialData;

  const DynamicPluginHostPage({
    super.key,
    required this.plugin,
    this.initialData,
  });

  @override
  ConsumerState<DynamicPluginHostPage> createState() =>
      _DynamicPluginHostPageState();
}

class _DynamicPluginHostPageState extends ConsumerState<DynamicPluginHostPage>
    with WidgetsBindingObserver
    implements PluginSessionUiHandler {
  late final PluginHostSession _session;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _session = PluginHostSession(
      plugin: widget.plugin,
      initialData: widget.initialData,
      uiHandler: this,
    );
    _session.addListener(_onSessionStateChanged);
    _session.start(registry: ref.read(pluginRegistryProvider));
  }

  void _onSessionStateChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _session.handleAppLifecycleState(state);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _session.removeListener(_onSessionStateChanged);
    _session.dispose();
    super.dispose();
  }

  // --- PluginSessionUiHandler 用户交互与弹窗协议实现 ---
  @override
  void showToast(String message) {
    if (mounted) PluginDialogService.showToast(context, message);
  }

  @override
  Future<void> showAlert(String title, String message) async {
    if (mounted) await PluginDialogService.showAlert(context, title, message);
  }

  @override
  Future<bool> showConfirm(String title, String message) async {
    if (!mounted) return false;
    return await PluginDialogService.showConfirm(context, title, message);
  }

  @override
  Future<String?> showPrompt({
    required String title,
    String? hint,
    String? defaultValue,
  }) async {
    if (!mounted) return null;
    return await PluginDialogService.showPrompt(
      context,
      title: title,
      hint: hint,
      defaultValue: defaultValue,
    );
  }

  @override
  Future<Map<String, dynamic>?> showPickItem({
    required String title,
    required List<String> items,
    int initialIndex = 0,
  }) async {
    if (!mounted) return null;
    return await PluginDialogService.showPickItem(
      context,
      title: title,
      items: items,
      initialIndex: initialIndex,
    );
  }

  @override
  Future<Map<String, dynamic>?> showBottomSheet({
    required String title,
    required List<String> items,
  }) async {
    if (!mounted) return null;
    return await PluginDialogService.showBottomSheet(
      context,
      title: title,
      items: items,
    );
  }

  @override
  void hideKeyboard() {
    if (mounted) {
      FocusScope.of(context).unfocus();
    }
  }

  @override
  Future<String?> pickDate({
    String? initialDate,
    String? firstDate,
    String? lastDate,
  }) async {
    if (!mounted) return null;
    return await PluginDialogService.pickDate(
      context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
    );
  }

  @override
  Future<String?> pickTime({String? initialTime}) async {
    if (!mounted) return null;
    return await PluginDialogService.pickTime(
      context,
      initialTime: initialTime,
    );
  }

  @override
  Future<bool> openPlugin(
    String targetPluginId, {
    Map<String, dynamic>? initialData,
  }) async {
    if (!mounted) return false;
    try {
      await context.push('/plugin/$targetPluginId', extra: initialData);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> requestPermission(PluginPermission permission) async {
    if (!mounted) return false;
    return await PluginPermissionPrompt.requestPermission(
      context,
      plugin: widget.plugin,
      permission: permission,
      ref: ref,
    );
  }

  @override
  Future<String?> simulateScanBarcode({String? prompt}) async {
    if (!mounted) return null;
    return await DesktopSimulationAdapter.simulateScanBarcode(
      context,
      prompt: prompt,
    );
  }

  @override
  Future<String?> simulateDecodeBarcode() async {
    if (!mounted) return null;
    return await DesktopSimulationAdapter.simulateDecodeBarcode(context);
  }

  @override
  Widget build(BuildContext context) {
    return PluginPageScaffold(
      title: widget.plugin.name,
      actions: [
        IconButton(
          icon: const Icon(Icons.bug_report_outlined),
          tooltip: '运行诊断与控制台',
          onPressed: () {
            PluginDiagnosticSheet.show(
              context,
              plugin: widget.plugin,
              runner: _session.runner,
              onReload: () =>
                  _session.reload(registry: ref.read(pluginRegistryProvider)),
            );
          },
        ),
      ],
      body: switch (_session.status) {
        PluginSessionStatus.loading =>
          const Center(child: CircularProgressIndicator()),
        PluginSessionStatus.error =>
          ErrorView(message: '插件运行错误:\n${_session.errorMessage}'),
        PluginSessionStatus.ready => _session.uiRootNode != null
            ? _session.renderer.build(context, _session.uiRootNode!)
            : const Center(child: Text('无 UI 描述')),
      },
    );
  }
}
