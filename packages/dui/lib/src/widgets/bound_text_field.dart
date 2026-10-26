import 'dart:async';
import 'package:flutter/material.dart';

/// 具备状态双向绑定、组合输入法防覆盖与输入防抖的增强文本输入框
class BoundTextField extends StatefulWidget {
  final String initialText;
  final String? hint;
  final String? label;
  final int maxLines;
  final bool readOnly;
  final ValueChanged<String> onChanged;
  final int debounceMs;

  const BoundTextField({
    super.key,
    required this.initialText,
    this.hint,
    this.label,
    required this.maxLines,
    required this.readOnly,
    required this.onChanged,
    this.debounceMs = 0,
  });

  @override
  State<BoundTextField> createState() => _BoundTextFieldState();
}

class _BoundTextFieldState extends State<BoundTextField> {
  late final TextEditingController _controller;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  void _handleChanged(String val) {
    if (widget.debounceMs <= 0) {
      widget.onChanged(val);
      return;
    }
    _debounceTimer?.cancel();
    _debounceTimer = Timer(Duration(milliseconds: widget.debounceMs), () {
      if (mounted) {
        widget.onChanged(val);
      }
    });
  }

  @override
  void didUpdateWidget(covariant BoundTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 若输入法处于拼音组合输入态，不中断当前选词组合
    if (_controller.value.isComposingRangeValid) return;
    if (widget.initialText != _controller.text) {
      final oldSelection = _controller.selection;
      _controller.text = widget.initialText;
      // 保持光标位置（限制在合法文本区间内），防止外部状态更新时光标跳跃至末尾或丢失
      if (oldSelection.isValid && oldSelection.baseOffset >= 0) {
        final newOffset =
            oldSelection.baseOffset.clamp(0, widget.initialText.length);
        _controller.selection = TextSelection.collapsed(offset: newOffset);
      }
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      maxLines: widget.maxLines,
      readOnly: widget.readOnly,
      decoration: InputDecoration(
        hintText: widget.hint,
        labelText: widget.label,
      ),
      onChanged: _handleChanged,
    );
  }
}
