import 'package:flutter/material.dart';

import '../dui_renderer.dart';
import '../dui_utils.dart';

/// 注册文本类组件工厂 (Text, SelectableText)
void registerTextFactories(DuiRenderer renderer) {
  final state = renderer.state;

  renderer.registerFactory('Text', (node) {
    final rawText = node.props['text']?.toString() ?? '';
    final keys = node.textKeys;
    Widget buildText() => Text(
          node.interpolate(rawText),
          style: DuiUtils.parseTextStyle(
              node.context, node.props['style']?.toString()),
          maxLines: DuiUtils.tryInt(node.props['maxLines']),
          overflow: node.props['overflow'] == 'ellipsis'
              ? TextOverflow.ellipsis
              : null,
        );
    if (keys.isEmpty) return buildText();
    return ListenableBuilder(
      listenable: state.listenableForKeys(keys),
      builder: (_, __) => buildText(),
    );
  });

  renderer.registerFactory('SelectableText', (node) {
    final rawText = node.props['text']?.toString() ?? '';
    final keys = node.textKeys;
    Widget buildText() => SelectableText(
          node.interpolate(rawText),
          style: DuiUtils.parseTextStyle(
              node.context, node.props['style']?.toString()),
        );
    if (keys.isEmpty) return buildText();
    return ListenableBuilder(
      listenable: state.listenableForKeys(keys),
      builder: (_, __) => buildText(),
    );
  });
}
