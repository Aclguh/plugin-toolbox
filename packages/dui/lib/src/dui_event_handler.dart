import 'package:flutter/services.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';
import 'dui_state.dart';

/// 动态界面的权限检查器回调
typedef DuiPermissionChecker = bool Function(PluginPermission permission);

/// DUI 动作执行接口，连接 DUI 事件与底层宿主逻辑或脚本引擎
abstract class DuiActionExecutor {
  /// 调用指定名称的 Lua 函数，传递参数列表 [args]
  void callLua(String functionName, [List<dynamic> args = const []]);

  /// 在界面上弹出轻量 Toast 提示
  void showToast(String message);
}

/// DUI 事件处理器：负责将组件树中的事件定义路由派发至对应执行器或状态存储
class DuiEventHandler {
  /// 动态 UI 状态机
  final DuiState state;

  /// 外部动作执行器
  final DuiActionExecutor executor;

  /// 插件权限校验器（为空时表示不受限环境）
  final DuiPermissionChecker? permissionChecker;

  /// 创建事件处理器
  DuiEventHandler({
    required this.state,
    required this.executor,
    this.permissionChecker,
  });

  /// 事件定义接受宽容的 Map 类型并做防御式取值：
  /// 第三方插件 JSON 的嵌套结构可能被解析为 `Map<dynamic, dynamic>`，
  /// 直接强转会抛 TypeError 使插件页面崩溃
  void handleEvent(Map? eventDef, [dynamic payload]) {
    if (eventDef == null) return;
    final action = eventDef['action']?.toString();
    if (action == null) return;

    switch (action) {
      case 'callLua':
        final func = eventDef['function']?.toString();
        if (func == null) return;
        final args =
            eventDef['args'] is List ? eventDef['args'] as List<dynamic> : const <dynamic>[];
        executor.callLua(func, args);
        break;

      case 'setState':
        final key = eventDef['key']?.toString();
        if (key == null) return;
        state.set(key, payload);
        break;

      case 'copyToClipboard':
        if (permissionChecker != null &&
            !permissionChecker!(PluginPermission.clipboard)) {
          executor.showToast('权限不足: 插件未声明 clipboard 权限');
          break;
        }
        final rawText = eventDef['text']?.toString() ?? '';
        final text = state.interpolate(rawText);
        Clipboard.setData(ClipboardData(text: text));
        executor.showToast('已复制到剪贴板');
        break;
    }
  }
}
