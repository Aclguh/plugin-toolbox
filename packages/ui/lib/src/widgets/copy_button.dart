import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CopyButton extends StatelessWidget {
  final String text;
  final String tooltip;

  const CopyButton({super.key, required this.text, this.tooltip = '复制'});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.content_copy, size: 20),
      tooltip: tooltip,
      onPressed: () {
        Clipboard.setData(ClipboardData(text: text));
        final messenger = ScaffoldMessenger.of(context);
        // 快速连点时先清空队列，防止 SnackBar 排队导致提示延迟消失
        messenger.clearSnackBars();
        messenger.showSnackBar(
          const SnackBar(
            content: Text('已复制到剪贴板'),
            duration: Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
    );
  }
}
