import 'package:flutter/material.dart';

import '../dui_renderer.dart';
import '../dui_state.dart';
import '../dui_utils.dart';

/// 注册文本类组件工厂 (Text, SelectableText)
void registerTextFactories(DuiRenderer renderer) {
  final state = renderer.state;

  renderer.registerFactory('Text', (node) {
    final rawText = node.props['text']?.toString() ?? '';
    final keys = DuiState.extractKeys(rawText);
    Widget buildText() => Text(
          state.interpolate(rawText),
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
    final keys = DuiState.extractKeys(rawText);
    Widget buildText() => SelectableText(
          state.interpolate(rawText),
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
