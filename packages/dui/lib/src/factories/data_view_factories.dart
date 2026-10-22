import 'package:flutter/material.dart';

import '../dui_code_view.dart';
import '../dui_color_picker.dart';
import '../dui_diff_view.dart';
import '../dui_renderer.dart';
import '../dui_state.dart';
import '../dui_tree_view.dart';
import '../dui_utils.dart';

/// 注册高级数据呈现与交互组件工厂 (CodeView, DiffView, TreeView, ColorPicker)
void registerDataViewFactories(DuiRenderer renderer) {
  final state = renderer.state;
  final eventHandler = renderer.eventHandler;

  // ---- 1. CodeView (代码/文本展示) ----
  renderer.registerFactory('CodeView', (node) {
    final rawText = node.props['text']?.toString() ??
        node.props['content']?.toString() ??
        '';
    final language = node.props['language']?.toString() ?? 'plaintext';
    final showLineNumbers = node.props['showLineNumbers'] != false;
    final wrap = node.props['wrap'] == true;
    final fontSize = DuiUtils.tryDouble(node.props['fontSize']) ?? 12.5;
    final showCopyButton = node.props['showCopyButton'] != false;
    final height = node.height;
    final maxCharacters =
        DuiUtils.tryInt(node.props['maxCharacters']) ?? 200000;

    final keys = DuiState.extractKeys(rawText);

    Widget buildView() {
      final text = state.interpolate(rawText);
      return DuiCodeView(
        text: text,
        language: language,
        showLineNumbers: showLineNumbers,
        wrap: wrap,
        fontSize: fontSize,
        showCopyButton: showCopyButton,
        height: height,
        maxCharacters: maxCharacters,
        onCopy: () {
          final onCopyEvent = node.events['onCopy'];
          if (onCopyEvent is Map) {
            eventHandler.handleEvent(onCopyEvent, {'text': text});
          }
        },
      );
    }

    if (keys.isEmpty) return buildView();
    return ListenableBuilder(
      listenable: state.listenableForKeys(keys),
      builder: (_, __) => buildView(),
    );
  });

  // ---- 2. DiffView (文本逐行比对) ----
  renderer.registerFactory('DiffView', (node) {
    final rawOld = node.props['oldText']?.toString() ?? '';
    final rawNew = node.props['newText']?.toString() ?? '';
    final showLineNumbers = node.props['showLineNumbers'] != false;
    final fontSize = DuiUtils.tryDouble(node.props['fontSize']) ?? 12.0;
    final showSummary = node.props['showSummary'] != false;
    final height = node.height;
    final maxCharacters =
        DuiUtils.tryInt(node.props['maxCharacters']) ?? 200000;

    final keys = {
      ...DuiState.extractKeys(rawOld),
      ...DuiState.extractKeys(rawNew),
    };

    Widget buildDiff() {
      final oldText = state.interpolate(rawOld);
      final newText = state.interpolate(rawNew);
      return DuiDiffView(
        oldText: oldText,
        newText: newText,
        showLineNumbers: showLineNumbers,
        fontSize: fontSize,
        showSummary: showSummary,
        height: height,
        maxCharacters: maxCharacters,
      );
    }

    if (keys.isEmpty) return buildDiff();
    return ListenableBuilder(
      listenable: state.listenableForKeys(keys),
      builder: (_, __) => buildDiff(),
    );
  });

  // ---- 3. TreeView (树形结构展示) ----
  renderer.registerFactory('TreeView', (node) {
    final rawData = node.props['data'];
    final expandAll = node.props['expandAll'] == true;
    final selectable = node.props['selectable'] != false;
    final showIcons = node.props['showIcons'] != false;
    final indent = DuiUtils.tryDouble(node.props['indent']) ?? 16.0;
    final height = node.height;

    final clickEvent = node.events['onNodeClick'] ?? node.events['onSelect'];

    void handleClick(Map<String, dynamic> info) {
      if (clickEvent is Map) {
        eventHandler.handleEvent(clickEvent, info);
      }
    }

    if (rawData is String) {
      final keys = DuiState.extractKeys(rawData);
      Widget buildTree() {
        final text = state.interpolate(rawData);
        return DuiTreeView(
          data: text,
          expandAll: expandAll,
          selectable: selectable,
          showIcons: showIcons,
          indent: indent,
          height: height,
          onNodeClick: handleClick,
        );
      }

      if (keys.isEmpty) return buildTree();
      return ListenableBuilder(
        listenable: state.listenableForKeys(keys),
        builder: (_, __) => buildTree(),
      );
    }

    return DuiTreeView(
      data: rawData,
      expandAll: expandAll,
      selectable: selectable,
      showIcons: showIcons,
      indent: indent,
      height: height,
      onNodeClick: handleClick,
    );
  });

  // ---- 4. ColorPicker (颜色选择与微调) ----
  renderer.registerFactory('ColorPicker', (node) {
    final rawValue = node.props['value']?.toString() ?? '#788CFF';
    final showPalette = node.props['showPalette'] != false;
    final rawPalette = node.props['palette'];
    List<String>? palette;
    if (rawPalette is List) {
      palette = [for (final p in rawPalette) p.toString()];
    }
    final showSliders = node.props['showSliders'] != false;
    final showAlpha = node.props['showAlpha'] == true;
    final showInput = node.props['showInput'] != false;
    final height = node.height;

    final keys = DuiState.extractKeys(rawValue);
    final singleKey = keys.length == 1 ? keys.first : null;

    final changedEvent = node.events['onChanged'];

    void handleChange(String newHex) {
      // 若属性绑定为单一状态键，自动回写触发双向同步
      if (singleKey != null) {
        state.set(singleKey, newHex);
      }
      if (changedEvent is Map) {
        eventHandler.handleEvent(changedEvent, {'value': newHex});
      }
    }

    Widget buildPicker() {
      final val = state.interpolate(rawValue);
      return DuiColorPicker(
        value: val.isNotEmpty ? val : '#788CFF',
        showPalette: showPalette,
        palette: palette,
        showSliders: showSliders,
        showAlpha: showAlpha,
        showInput: showInput,
        height: height,
        onChanged: handleChange,
      );
    }

    if (keys.isEmpty) return buildPicker();
    return ListenableBuilder(
      listenable: state.listenableForKeys(keys),
      builder: (_, __) => buildPicker(),
    );
  });
}
