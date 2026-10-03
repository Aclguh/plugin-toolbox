import 'package:flutter/services.dart';
import 'dui_state.dart';

abstract class DuiActionExecutor {
  void callLua(String functionName, [List<dynamic> args = const []]);
  void showToast(String message);
}

class DuiEventHandler {
  final DuiState state;
  final DuiActionExecutor executor;

  DuiEventHandler({
    required this.state,
    required this.executor,
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
        final rawText = eventDef['text']?.toString() ?? '';
        final text = state.interpolate(rawText);
        Clipboard.setData(ClipboardData(text: text));
        executor.showToast('已复制到剪贴板');
        break;
    }
  }
}
