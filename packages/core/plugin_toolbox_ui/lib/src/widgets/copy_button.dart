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
        ScaffoldMessenger.of(context).showSnackBar(
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
