import 'dart:io';
import 'package:flutter/material.dart';
import 'dui_state.dart';
import 'dui_event_handler.dart';
import 'dui_utils.dart';

class DuiRenderer {
  final DuiState state;
  final DuiEventHandler eventHandler;
  final Directory? pluginRootDir;

  DuiRenderer({
    required this.state,
    required this.eventHandler,
    this.pluginRootDir,
  });

  /// 将 JSON 节点递归转换为 Flutter Widget
  Widget buildWidget(BuildContext context, Map<String, dynamic> node) {
    // 1. 检查条件可见性
    final visibleExpr = node['visible'];
    if (!state.evaluateVisible(visibleExpr)) {
      return const SizedBox.shrink();
    }

    final type = node['type'] as String? ?? 'Container';
    final props = node['props'] as Map<String, dynamic>? ?? {};
    final childrenRaw = node['children'] as List<dynamic>? ?? [];
    final events = node['events'] as Map<String, dynamic>? ?? {};
    final ref = node['ref'] as String?;

    switch (type) {
      // 布局类
      case 'Column':
        return Column(
          crossAxisAlignment: _parseCrossAxis(props['crossAxisAlignment']),
          mainAxisAlignment: _parseMainAxis(props['mainAxisAlignment']),
          mainAxisSize: props['mainAxisSize'] == 'min' ? MainAxisSize.min : MainAxisSize.max,
          children: childrenRaw
              .map((c) => buildWidget(context, Map<String, dynamic>.from(c as Map)))
              .toList(),
        );

      case 'Row':
        return Row(
          crossAxisAlignment: _parseCrossAxis(props['crossAxisAlignment']),
          mainAxisAlignment: _parseMainAxis(props['mainAxisAlignment']),
          mainAxisSize: props['mainAxisSize'] == 'min' ? MainAxisSize.min : MainAxisSize.max,
          children: childrenRaw
              .map((c) => buildWidget(context, Map<String, dynamic>.from(c as Map)))
              .toList(),
        );

      case 'Stack':
        return Stack(
          alignment: Alignment.center,
          children: childrenRaw
              .map((c) => buildWidget(context, Map<String, dynamic>.from(c as Map)))
              .toList(),
        );

      case 'Padding':
        final childNode = childrenRaw.isNotEmpty ? childrenRaw.first as Map : null;
        return Padding(
          padding: DuiUtils.parsePadding(props['padding']),
          child: childNode != null
              ? buildWidget(context, Map<String, dynamic>.from(childNode))
              : const SizedBox.shrink(),
        );

      case 'Center':
        final childNode = childrenRaw.isNotEmpty ? childrenRaw.first as Map : null;
        return Center(
          child: childNode != null
              ? buildWidget(context, Map<String, dynamic>.from(childNode))
              : const SizedBox.shrink(),
        );

      case 'Expanded':
        final childNode = childrenRaw.isNotEmpty ? childrenRaw.first as Map : null;
        return Expanded(
          flex: (props['flex'] as num?)?.toInt() ?? 1,
          child: childNode != null
              ? buildWidget(context, Map<String, dynamic>.from(childNode))
              : const SizedBox.shrink(),
        );

      case 'SizedBox':
        return SizedBox(
          width: (props['width'] as num?)?.toDouble(),
          height: (props['height'] as num?)?.toDouble(),
          child: childrenRaw.isNotEmpty
              ? buildWidget(context, Map<String, dynamic>.from(childrenRaw.first as Map))
              : null,
        );

      case 'SingleChildScrollView':
        final childNode = childrenRaw.isNotEmpty ? childrenRaw.first as Map : null;
        return SingleChildScrollView(
          padding: DuiUtils.parsePadding(props['padding']),
          child: childNode != null
              ? buildWidget(context, Map<String, dynamic>.from(childNode))
              : const SizedBox.shrink(),
        );

      // 文本类
      case 'Text':
        final rawText = props['text'] as String? ?? '';
        return Text(
          state.interpolate(rawText),
          style: DuiUtils.parseTextStyle(context, props['style'] as String?),
          maxLines: (props['maxLines'] as num?)?.toInt(),
          overflow: props['overflow'] == 'ellipsis' ? TextOverflow.ellipsis : null,
        );

      case 'SelectableText':
        final rawText = props['text'] as String? ?? '';
        return SelectableText(
          state.interpolate(rawText),
          style: DuiUtils.parseTextStyle(context, props['style'] as String?),
        );

      // 输入框 (带双向绑定)
      case 'TextField':
        final currentVal = ref != null ? (state.get(ref)?.toString() ?? '') : '';
        return _BoundTextField(
          initialText: currentVal,
          hint: props['hint'] as String?,
          label: props['label'] as String?,
          maxLines: (props['maxLines'] as num?)?.toInt() ?? 1,
          readOnly: props['readOnly'] == true,
          onChanged: (val) {
            if (ref != null) {
              state.set(ref, val);
            }
            if (events.containsKey('onChanged')) {
              eventHandler.handleEvent(events['onChanged'] as Map<String, dynamic>?, val);
            }
          },
        );

      // 按钮类
      case 'FilledButton':
        final label = state.interpolate(props['text'] as String? ?? '');
        final iconStr = props['icon'] as String?;
        return iconStr != null
            ? FilledButton.icon(
                icon: Icon(DuiUtils.parseIcon(iconStr)),
                label: Text(label),
                onPressed: () => eventHandler.handleEvent(events['onPressed'] as Map<String, dynamic>?),
              )
            : FilledButton(
                onPressed: () => eventHandler.handleEvent(events['onPressed'] as Map<String, dynamic>?),
                child: Text(label),
              );

      case 'OutlinedButton':
        final label = state.interpolate(props['text'] as String? ?? '');
        final iconStr = props['icon'] as String?;
        return iconStr != null
            ? OutlinedButton.icon(
                icon: Icon(DuiUtils.parseIcon(iconStr)),
                label: Text(label),
                onPressed: () => eventHandler.handleEvent(events['onPressed'] as Map<String, dynamic>?),
              )
            : OutlinedButton(
                onPressed: () => eventHandler.handleEvent(events['onPressed'] as Map<String, dynamic>?),
                child: Text(label),
              );

      case 'IconButton':
        return IconButton(
          icon: Icon(DuiUtils.parseIcon(props['icon'] as String?)),
          tooltip: props['tooltip'] as String?,
          onPressed: () => eventHandler.handleEvent(events['onPressed'] as Map<String, dynamic>?),
        );

      // 容器类
      case 'Card':
        return Card(
          elevation: (props['elevation'] as num?)?.toDouble() ?? 0,
          child: childrenRaw.isNotEmpty
              ? buildWidget(context, Map<String, dynamic>.from(childrenRaw.first as Map))
              : const SizedBox.shrink(),
        );

      case 'Container':
        return Container(
          padding: DuiUtils.parsePadding(props['padding']),
          width: (props['width'] as num?)?.toDouble(),
          height: (props['height'] as num?)?.toDouble(),
          decoration: BoxDecoration(
            borderRadius: props['borderRadius'] != null
                ? BorderRadius.circular((props['borderRadius'] as num).toDouble())
                : null,
          ),
          child: childrenRaw.isNotEmpty
              ? buildWidget(context, Map<String, dynamic>.from(childrenRaw.first as Map))
              : null,
        );

      // 列表类
      case 'ListView':
        return ListView(
          shrinkWrap: props['shrinkWrap'] == true,
          padding: DuiUtils.parsePadding(props['padding']),
          children: childrenRaw
              .map((c) => buildWidget(context, Map<String, dynamic>.from(c as Map)))
              .toList(),
        );

      case 'ListTile':
        return ListTile(
          title: Text(state.interpolate(props['title'] as String? ?? '')),
          subtitle: props['subtitle'] != null ? Text(state.interpolate(props['subtitle'].toString())) : null,
          leading: props['leading'] != null ? Icon(DuiUtils.parseIcon(props['leading'].toString())) : null,
          onTap: () => eventHandler.handleEvent(events['onTap'] as Map<String, dynamic>?),
        );

      // 图片显示 (从插件本地沙箱目录加载)
      case 'Image':
        final src = props['src'] as String? ?? '';
        final file = File('${pluginRootDir?.path}/$src');
        if (file.existsSync()) {
          return Image.file(
            file,
            width: (props['width'] as num?)?.toDouble(),
            height: (props['height'] as num?)?.toDouble(),
            fit: BoxFit.contain,
          );
        }
        return const SizedBox.shrink();

      default:
        return const SizedBox.shrink();
    }
  }

  CrossAxisAlignment _parseCrossAxis(String? val) {
    switch (val) {
      case 'start': return CrossAxisAlignment.start;
      case 'end': return CrossAxisAlignment.end;
      case 'center': return CrossAxisAlignment.center;
      case 'stretch': return CrossAxisAlignment.stretch;
      default: return CrossAxisAlignment.start;
    }
  }

  MainAxisAlignment _parseMainAxis(String? val) {
    switch (val) {
      case 'start': return MainAxisAlignment.start;
      case 'end': return MainAxisAlignment.end;
      case 'center': return MainAxisAlignment.center;
      case 'spaceBetween': return MainAxisAlignment.spaceBetween;
      default: return MainAxisAlignment.start;
    }
  }
}

class _BoundTextField extends StatefulWidget {
  final String initialText;
  final String? hint;
  final String? label;
  final int maxLines;
  final bool readOnly;
  final ValueChanged<String> onChanged;

  const _BoundTextField({
    required this.initialText,
    this.hint,
    this.label,
    required this.maxLines,
    required this.readOnly,
    required this.onChanged,
  });

  @override
  State<_BoundTextField> createState() => _BoundTextFieldState();
}

class _BoundTextFieldState extends State<_BoundTextField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void didUpdateWidget(covariant _BoundTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialText != _controller.text) {
      _controller.text = widget.initialText;
    }
  }

  @override
  void dispose() {
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
      onChanged: widget.onChanged,
    );
  }
}
