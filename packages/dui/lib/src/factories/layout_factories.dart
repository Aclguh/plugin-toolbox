import 'package:flutter/material.dart';

import '../dui_renderer.dart';
import '../dui_state.dart';
import '../dui_utils.dart';

/// 注册布局与容器类组件工厂 (Column, Row, Stack, Container, etc.)
void registerLayoutFactories(DuiRenderer renderer) {
  final state = renderer.state;
  final eventHandler = renderer.eventHandler;

  CrossAxisAlignment parseCrossAxis(String? val) {
    switch (val) {
      case 'start': return CrossAxisAlignment.start;
      case 'end': return CrossAxisAlignment.end;
      case 'center': return CrossAxisAlignment.center;
      case 'stretch': return CrossAxisAlignment.stretch;
      default: return CrossAxisAlignment.start;
    }
  }

  MainAxisAlignment parseMainAxis(String? val) {
    switch (val) {
      case 'start': return MainAxisAlignment.start;
      case 'end': return MainAxisAlignment.end;
      case 'center': return MainAxisAlignment.center;
      case 'spaceBetween': return MainAxisAlignment.spaceBetween;
      default: return MainAxisAlignment.start;
    }
  }

  WrapAlignment parseWrapAlignment(String? val) {
    switch (val) {
      case 'center': return WrapAlignment.center;
      case 'end': return WrapAlignment.end;
      case 'spaceBetween': return WrapAlignment.spaceBetween;
      case 'spaceAround': return WrapAlignment.spaceAround;
      case 'spaceEvenly': return WrapAlignment.spaceEvenly;
      default: return WrapAlignment.start;
    }
  }

  renderer.registerFactory('Column', (node) => Column(
        crossAxisAlignment: parseCrossAxis(node.props['crossAxisAlignment']),
        mainAxisAlignment: parseMainAxis(node.props['mainAxisAlignment']),
        mainAxisSize: node.props['mainAxisSize'] == 'min'
            ? MainAxisSize.min
            : MainAxisSize.max,
        children: node.childrenWidgets,
      ));

  renderer.registerFactory('Row', (node) => Row(
        crossAxisAlignment: parseCrossAxis(node.props['crossAxisAlignment']),
        mainAxisAlignment: parseMainAxis(node.props['mainAxisAlignment']),
        mainAxisSize: node.props['mainAxisSize'] == 'min'
            ? MainAxisSize.min
            : MainAxisSize.max,
        children: node.childrenWidgets,
      ));

  renderer.registerFactory('Stack', (node) => Stack(
        alignment: Alignment.center,
        children: node.childrenWidgets,
      ));

  renderer.registerFactory('Padding', (node) => Padding(
        padding: DuiUtils.parsePadding(node.props['padding']),
        child: node.firstChild,
      ));

  renderer.registerFactory('Center', (node) => Center(child: node.firstChild));

  renderer.registerFactory('Expanded', (node) => Expanded(
        flex: DuiUtils.tryInt(node.props['flex']) ?? 1,
        child: node.firstChild,
      ));

  renderer.registerFactory('SizedBox', (node) => SizedBox(
        width: node.width,
        height: node.height,
        child: node.children.isNotEmpty ? node.firstChild : null,
      ));

  renderer.registerFactory('SingleChildScrollView', (node) =>
      SingleChildScrollView(
        padding: DuiUtils.parsePadding(node.props['padding']),
        child: node.firstChild,
      ));

  renderer.registerFactory('Card', (node) => Card(
        elevation: DuiUtils.tryDouble(node.props['elevation']) ?? 0,
        child: node.firstChild,
      ));

  renderer.registerFactory('Container', (node) {
    final borderRadiusVal = DuiUtils.tryDouble(node.props['borderRadius']);
    final colorRaw = node.props['color']?.toString() ?? '';
    final keys = DuiState.extractKeys(colorRaw);

    Widget buildContainer() => Container(
          padding: DuiUtils.parsePadding(node.props['padding']),
          width: node.width,
          height: node.height,
          decoration: BoxDecoration(
            color: DuiUtils.parseColor(state.interpolate(colorRaw)),
            borderRadius: borderRadiusVal != null
                ? BorderRadius.circular(borderRadiusVal)
                : null,
          ),
          child: node.children.isNotEmpty ? node.firstChild : null,
        );

    if (keys.isEmpty) return buildContainer();
    return ListenableBuilder(
      listenable: state.listenableForKeys(keys),
      builder: (_, __) => buildContainer(),
    );
  });

  renderer.registerFactory('ListView', (node) => ListView(
        shrinkWrap: DuiUtils.tryBool(node.props['shrinkWrap']),
        padding: DuiUtils.parsePadding(node.props['padding']),
        children: node.childrenWidgets,
      ));

  renderer.registerFactory('ListTile', (node) => ListTile(
        title:
            Text(state.interpolate(node.props['title']?.toString() ?? '')),
        subtitle: node.props['subtitle'] != null
            ? Text(state.interpolate(node.props['subtitle'].toString()))
            : null,
        leading: node.props['leading'] != null
            ? Icon(DuiUtils.parseIcon(node.props['leading'].toString()))
            : null,
        onTap: () => eventHandler.handleEvent(node.events['onTap']),
      ));

  renderer.registerFactory('Wrap', (node) => Wrap(
        spacing: DuiUtils.tryDouble(node.props['spacing']) ?? 0.0,
        runSpacing: DuiUtils.tryDouble(node.props['runSpacing']) ?? 0.0,
        alignment: parseWrapAlignment(node.props['alignment']?.toString()),
        children: node.childrenWidgets,
      ));

  renderer.registerFactory('Divider', (node) => Divider(
        height: DuiUtils.tryDouble(node.props['height']),
        thickness: DuiUtils.tryDouble(node.props['thickness']),
        color: DuiUtils.parseColor(
            state.interpolate(node.props['color']?.toString() ?? '')),
      ));
}
