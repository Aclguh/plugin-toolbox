import 'package:flutter/material.dart';

import '../dui_renderer.dart';
import '../dui_state.dart';
import '../dui_utils.dart';
import '../widgets/bound_text_field.dart';
import '../widgets/dui_tabs.dart';

export '../widgets/bound_text_field.dart';
export '../widgets/dui_tabs.dart';

/// 注册输入与交互控制类组件工厂 (TextField, Button, Switch, Slider, Tabs, etc.)
void registerInputFactories(DuiRenderer renderer) {
  final state = renderer.state;
  final eventHandler = renderer.eventHandler;

  // ---- 输入框 (带双向绑定) ----
  renderer.registerFactory('TextField', (node) {
    Widget buildTextField() {
      final currentVal =
          node.ref != null ? (state.get(node.ref!)?.toString() ?? '') : '';
      return BoundTextField(
        initialText: currentVal,
        hint: node.props['hint']?.toString(),
        label: node.props['label']?.toString(),
        maxLines: DuiUtils.tryInt(node.props['maxLines']) ?? 1,
        readOnly: DuiUtils.tryBool(node.props['readOnly']),
        debounceMs: DuiUtils.tryInt(node.props['debounceMs']) ?? 0,
        onChanged: (val) {
          if (node.ref != null) {
            state.set(node.ref!, val);
          }
          if (node.events.containsKey('onChanged')) {
            eventHandler.handleEvent(node.events['onChanged'], val);
          }
        },
      );
    }

    if (node.ref != null) {
      return ListenableBuilder(
        listenable: state.listenableForKey(node.ref!),
        builder: (_, __) => buildTextField(),
      );
    }
    return buildTextField();
  });

  Widget buildFilledButton(DuiNodeContext node) {
    final rawText = node.props['text']?.toString() ?? '';
    final keys = node.textKeys;
    final iconStr = node.props['icon']?.toString();
    void onPressed() => node.handleEvent(node.events['onPressed']);

    Widget buildButton() {
      final label = node.interpolate(rawText);
      return iconStr != null
          ? FilledButton.icon(
              icon: Icon(DuiUtils.parseIcon(iconStr)),
              label: Text(label),
              onPressed: onPressed,
            )
          : FilledButton(onPressed: onPressed, child: Text(label));
    }

    if (keys.isNotEmpty) {
      return ListenableBuilder(
        listenable: state.listenableForKeys(keys),
        builder: (_, __) => buildButton(),
      );
    }
    return buildButton();
  }

  Widget buildOutlinedButton(DuiNodeContext node) {
    final rawText = node.props['text']?.toString() ?? '';
    final keys = node.textKeys;
    final iconStr = node.props['icon']?.toString();
    void onPressed() => node.handleEvent(node.events['onPressed']);

    Widget buildButton() {
      final label = node.interpolate(rawText);
      return iconStr != null
          ? OutlinedButton.icon(
              icon: Icon(DuiUtils.parseIcon(iconStr)),
              label: Text(label),
              onPressed: onPressed,
            )
          : OutlinedButton(onPressed: onPressed, child: Text(label));
    }

    if (keys.isNotEmpty) {
      return ListenableBuilder(
        listenable: state.listenableForKeys(keys),
        builder: (_, __) => buildButton(),
      );
    }
    return buildButton();
  }

  renderer.registerFactory('FilledButton', buildFilledButton);
  renderer.registerFactory('OutlinedButton', buildOutlinedButton);
  renderer.registerFactory('Button', (node) {
    final type = node.props['type']?.toString().toLowerCase();
    if (type == 'outlined') {
      return buildOutlinedButton(node);
    }
    return buildFilledButton(node);
  });

  renderer.registerFactory(
      'IconButton',
      (node) => IconButton(
            icon: Icon(DuiUtils.parseIcon(node.props['icon']?.toString())),
            tooltip: node.props['tooltip']?.toString(),
            onPressed: () => eventHandler.handleEvent(node.events['onPressed']),
          ));

  // ---- 进度条 (ProgressBar) ----
  renderer.registerFactory('ProgressBar', (node) {
    final rawVal = node.props['value']?.toString() ?? '';
    final keys = DuiState.extractKeys(rawVal);
    Widget buildProgress() {
      final interpolated = state.interpolate(rawVal);
      final val = DuiUtils.tryDouble(interpolated);
      return LinearProgressIndicator(
        value: val,
        color: DuiUtils.parseColor(
            state.interpolate(node.props['color']?.toString() ?? '')),
        backgroundColor: DuiUtils.parseColor(
            state.interpolate(node.props['backgroundColor']?.toString() ?? '')),
      );
    }

    if (keys.isEmpty) return buildProgress();
    return ListenableBuilder(
      listenable: state.listenableForKeys(keys),
      builder: (_, __) => buildProgress(),
    );
  });

  // ---- 开关控件 (Switch) ----
  renderer.registerFactory('Switch', (node) {
    final label = node.props['label']?.toString();
    final ref = node.ref;

    Widget buildSwitch() {
      bool currentVal = false;
      if (ref != null) {
        final stateVal = state.get(ref);
        currentVal = (stateVal == true || stateVal == 'true');
      } else if (node.props['value'] != null) {
        final rawVal = state.interpolate(node.props['value'].toString());
        currentVal = (rawVal == 'true' || rawVal == '1');
      }

      void onChanged(bool val) {
        if (ref != null) {
          state.set(ref, val);
        }
        if (node.events.containsKey('onChanged')) {
          eventHandler.handleEvent(node.events['onChanged'], val);
        }
      }

      final switchWidget = Switch(
        value: currentVal,
        onChanged: onChanged,
      );

      if (label != null && label.isNotEmpty) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(state.interpolate(label)),
            const SizedBox(width: 8),
            switchWidget,
          ],
        );
      }
      return switchWidget;
    }

    if (ref != null) {
      return ListenableBuilder(
        listenable: state.listenableForKeys({ref}),
        builder: (_, __) => buildSwitch(),
      );
    }
    return buildSwitch();
  });

  // ---- 滑块控件 (Slider) ----
  renderer.registerFactory('Slider', (node) {
    final ref = node.ref;
    final min = DuiUtils.tryDouble(node.props['min']) ?? 0.0;
    final max = DuiUtils.tryDouble(node.props['max']) ?? 1.0;
    final divisions = DuiUtils.tryInt(node.props['divisions']);

    Widget buildSlider() {
      double currentVal = min;
      if (ref != null) {
        final stateVal = state.get(ref);
        currentVal = DuiUtils.tryDouble(stateVal) ?? min;
      } else if (node.props['value'] != null) {
        final rawVal = state.interpolate(node.props['value'].toString());
        currentVal = DuiUtils.tryDouble(rawVal) ?? min;
      }
      final clampedVal = currentVal.clamp(min, max);

      return Slider(
        value: clampedVal,
        min: min,
        max: max,
        divisions: divisions,
        onChanged: (val) {
          if (ref != null) {
            state.set(ref, val);
          }
          if (node.events.containsKey('onChanged')) {
            eventHandler.handleEvent(node.events['onChanged'], val);
          }
        },
      );
    }

    if (ref != null) {
      return ListenableBuilder(
        listenable: state.listenableForKeys({ref}),
        builder: (_, __) => buildSlider(),
      );
    }
    return buildSlider();
  });

  // ---- 下拉单选 (Dropdown) ----
  renderer.registerFactory('Dropdown', (node) {
    final ref = node.ref;
    final rawItems = node.props['items'] as List<dynamic>? ?? const [];
    final items = rawItems.map((e) => e.toString()).toList();
    final hint = node.props['hint']?.toString();

    Widget buildDropdown() {
      String? currentVal;
      if (ref != null) {
        final stateVal = state.get(ref)?.toString();
        if (items.contains(stateVal)) {
          currentVal = stateVal;
        }
      } else if (node.props['value'] != null) {
        final rawVal = state.interpolate(node.props['value'].toString());
        if (items.contains(rawVal)) {
          currentVal = rawVal;
        }
      }

      return DropdownButton<String>(
        value: currentVal,
        hint: hint != null ? Text(state.interpolate(hint)) : null,
        items: items
            .map((it) => DropdownMenuItem(value: it, child: Text(it)))
            .toList(),
        onChanged: (val) {
          if (val != null) {
            if (ref != null) {
              state.set(ref, val);
            }
            if (node.events.containsKey('onChanged')) {
              eventHandler.handleEvent(node.events['onChanged'], val);
            }
          }
        },
      );
    }

    if (ref != null) {
      return ListenableBuilder(
        listenable: state.listenableForKeys({ref}),
        builder: (_, __) => buildDropdown(),
      );
    }
    return buildDropdown();
  });

  // ---- 标签页容器 (Tabs / TabBar) ----
  Widget buildTabs(DuiNodeContext node) {
    final rawTabs = node.props['tabs'] as List<dynamic>? ?? const [];
    final tabs = rawTabs.map((e) => state.interpolate(e.toString())).toList();
    final ref = node.ref;
    final initialIndex = DuiUtils.tryInt(node.props['initialIndex']) ?? 0;
    final children = node.childrenWidgets;

    return DuiTabs(
      tabTitles: tabs,
      initialIndex: initialIndex,
      refKey: ref,
      state: state,
      onChanged: (idx) {
        if (node.events.containsKey('onChanged')) {
          eventHandler.handleEvent(node.events['onChanged'], idx);
        }
      },
      children: children,
    );
  }

  renderer.registerFactory('Tabs', buildTabs);
  renderer.registerFactory('TabBar', buildTabs);
}
