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

  void handleEvent(Map<String, dynamic>? eventDef, [dynamic payload]) {
    if (eventDef == null) return;
    final action = eventDef['action'] as String?;
    if (action == null) return;

    switch (action) {
      case 'callLua':
        final func = eventDef['function'] as String;
        final args = eventDef['args'] as List<dynamic>? ?? [];
        executor.callLua(func, args);
        break;

      case 'setState':
        final key = eventDef['key'] as String;
        state.set(key, payload);
        break;

      case 'copyToClipboard':
        final rawText = eventDef['text'] as String? ?? '';
        final text = state.interpolate(rawText);
        Clipboard.setData(ClipboardData(text: text));
        executor.showToast('已复制到剪贴板');
        break;
    }
  }
}
