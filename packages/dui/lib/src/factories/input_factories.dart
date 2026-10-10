import 'package:flutter/material.dart';

import '../dui_renderer.dart';
import '../dui_state.dart';
import '../dui_utils.dart';

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

  // ---- 按钮类 ----
  renderer.registerFactory('FilledButton', (node) {
    final rawText = node.props['text']?.toString() ?? '';
    final keys = DuiState.extractKeys(rawText);
    final iconStr = node.props['icon']?.toString();
    void onPressed() =>
        eventHandler.handleEvent(node.events['onPressed']);

    Widget buildButton() {
      final label = state.interpolate(rawText);
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
  });

  renderer.registerFactory('OutlinedButton', (node) {
    final rawText = node.props['text']?.toString() ?? '';
    final keys = DuiState.extractKeys(rawText);
    final iconStr = node.props['icon']?.toString();
    void onPressed() =>
        eventHandler.handleEvent(node.events['onPressed']);

    Widget buildButton() {
      final label = state.interpolate(rawText);
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
  });

  renderer.registerFactory('IconButton', (node) => IconButton(
        icon: Icon(DuiUtils.parseIcon(node.props['icon']?.toString())),
        tooltip: node.props['tooltip']?.toString(),
        onPressed: () =>
            eventHandler.handleEvent(node.events['onPressed']),
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
        backgroundColor: DuiUtils.parseColor(state
            .interpolate(node.props['backgroundColor']?.toString() ?? '')),
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

class BoundTextField extends StatefulWidget {
  final String initialText;
  final String? hint;
  final String? label;
  final int maxLines;
  final bool readOnly;
  final ValueChanged<String> onChanged;

  const BoundTextField({
    super.key,
    required this.initialText,
    this.hint,
    this.label,
    required this.maxLines,
    required this.readOnly,
    required this.onChanged,
  });

  @override
  State<BoundTextField> createState() => _BoundTextFieldState();
}

class _BoundTextFieldState extends State<BoundTextField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void didUpdateWidget(covariant BoundTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
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

class DuiTabs extends StatefulWidget {
  final List<String> tabTitles;
  final List<Widget> children;
  final int initialIndex;
  final String? refKey;
  final DuiState state;
  final ValueChanged<int>? onChanged;

  const DuiTabs({
    super.key,
    required this.tabTitles,
    required this.children,
    this.initialIndex = 0,
    this.refKey,
    required this.state,
    this.onChanged,
  });

  @override
  State<DuiTabs> createState() => _DuiTabsState();
}

class _DuiTabsState extends State<DuiTabs> {
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = _resolveCurrentIndex();
  }

  int _resolveCurrentIndex() {
    if (widget.refKey != null) {
      final val = widget.state.get(widget.refKey!);
      final parsed = DuiUtils.tryInt(val);
      if (parsed != null && parsed >= 0 && parsed < widget.children.length) {
        return parsed;
      }
    }
    return widget.initialIndex
        .clamp(0, widget.children.isNotEmpty ? widget.children.length - 1 : 0);
  }

  @override
  void didUpdateWidget(covariant DuiTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextIndex = _resolveCurrentIndex();
    if (nextIndex != _currentIndex) {
      setState(() {
        _currentIndex = nextIndex;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final titles = widget.tabTitles.isNotEmpty
        ? widget.tabTitles
        : List.generate(widget.children.length, (i) => 'Tab ${i + 1}');

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (titles.isNotEmpty)
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                for (int i = 0; i < titles.length; i++)
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        if (_currentIndex != i) {
                          setState(() {
                            _currentIndex = i;
                          });
                          if (widget.refKey != null) {
                            widget.state.set(widget.refKey!, i);
                          }
                          widget.onChanged?.call(i);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: _currentIndex == i
                              ? colorScheme.primary
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          titles[i],
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: _currentIndex == i
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: _currentIndex == i
                                ? colorScheme.onPrimary
                                : colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        if (widget.children.isNotEmpty &&
            _currentIndex < widget.children.length)
          widget.children[_currentIndex]
        else
          const SizedBox.shrink(),
      ],
    );
  }
}
