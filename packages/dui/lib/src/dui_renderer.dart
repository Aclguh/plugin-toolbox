import 'dart:io';

import 'package:flutter/material.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';

import 'dui_event_handler.dart';
import 'dui_markdown.dart';
import 'dui_pixel_grid.dart';
import 'dui_state.dart';
import 'dui_utils.dart';

/// 组件工厂上下文：封装单个 JSON 节点的解析结果，
/// 供 [DuiWidgetFactory] 构建组件时取用属性、子节点与事件。
class DuiNodeContext {
  final BuildContext context;
  final DuiRenderer renderer;
  final Map<String, dynamic> props;
  final List<Map<String, dynamic>> children;
  final Map<String, dynamic> events;
  final String? ref;

  const DuiNodeContext({
    required this.context,
    required this.renderer,
    required this.props,
    required this.children,
    required this.events,
    required this.ref,
  });

  /// 构建第 [index] 个子节点
  Widget childAt(int index) => renderer.buildWidget(context, children[index]);

  /// 首个子节点；无子节点时返回占位
  Widget get firstChild =>
      children.isNotEmpty ? childAt(0) : const SizedBox.shrink();

  /// 构建全部子节点
  List<Widget> get childrenWidgets => [for (var i = 0; i < children.length; i++) childAt(i)];

  // ---- 常用安全属性读取快捷方式 ----
  double? get width => DuiUtils.tryDouble(props['width']);
  double? get height => DuiUtils.tryDouble(props['height']);
}

typedef DuiWidgetFactory = Widget Function(DuiNodeContext node);

class DuiRenderer {
  final DuiState state;
  final DuiEventHandler eventHandler;
  final Directory? pluginRootDir;

  final Map<String, DuiWidgetFactory> _factories = {};

  DuiRenderer({
    required this.state,
    required this.eventHandler,
    this.pluginRootDir,
  }) {
    _registerBuiltinFactories();
  }

  /// 注册（或覆盖）组件类型工厂。
  ///
  /// 渲染器对扩展开放：新增组件类型无需修改渲染器本身，
  /// 宿主或高级插件可通过注册自定义工厂扩展组件集。
  void registerFactory(String type, DuiWidgetFactory factory) {
    _factories[type] = factory;
  }

  /// 顶层构建入口：以 ListenableBuilder 订阅 [state]，
  /// 状态变更后自动重建声明式组件树，宿主页面无需再手动 setState。
  Widget build(BuildContext context, Map<String, dynamic> rootNode) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) => buildWidget(context, rootNode),
    );
  }

  /// 将 JSON 节点递归转换为 Flutter Widget
  Widget buildWidget(BuildContext context, Map<String, dynamic> node) {
    // 1. 检查条件可见性
    final visibleExpr = node['visible'];
    if (!state.evaluateVisible(visibleExpr)) {
      return const SizedBox.shrink();
    }

    final type = node['type']?.toString() ?? 'Container';
    final props = _asMap(node['props']);
    final childrenRaw = node['children'] as List<dynamic>? ?? const [];
    final events = _asMap(node['events']);
    final ref = node['ref']?.toString();

    final factory = _factories[type];
    if (factory == null) {
      return const SizedBox.shrink();
    }

    final parsedChildren = <Map<String, dynamic>>[];
    for (final c in childrenRaw) {
      if (c is Map) parsedChildren.add(_asMap(c));
    }

    return factory(
      DuiNodeContext(
        context: context,
        renderer: this,
        props: props,
        children: parsedChildren,
        events: events,
        ref: ref,
      ),
    );
  }

  void _registerBuiltinFactories() {
    // ---- 布局类 ----
    registerFactory('Column', (node) => Column(
          crossAxisAlignment: _parseCrossAxis(node.props['crossAxisAlignment']),
          mainAxisAlignment: _parseMainAxis(node.props['mainAxisAlignment']),
          mainAxisSize: node.props['mainAxisSize'] == 'min'
              ? MainAxisSize.min
              : MainAxisSize.max,
          children: node.childrenWidgets,
        ));

    registerFactory('Row', (node) => Row(
          crossAxisAlignment: _parseCrossAxis(node.props['crossAxisAlignment']),
          mainAxisAlignment: _parseMainAxis(node.props['mainAxisAlignment']),
          mainAxisSize: node.props['mainAxisSize'] == 'min'
              ? MainAxisSize.min
              : MainAxisSize.max,
          children: node.childrenWidgets,
        ));

    registerFactory('Stack', (node) => Stack(
          alignment: Alignment.center,
          children: node.childrenWidgets,
        ));

    registerFactory('Padding', (node) => Padding(
          padding: DuiUtils.parsePadding(node.props['padding']),
          child: node.firstChild,
        ));

    registerFactory('Center', (node) => Center(child: node.firstChild));

    registerFactory('Expanded', (node) => Expanded(
          flex: DuiUtils.tryInt(node.props['flex']) ?? 1,
          child: node.firstChild,
        ));

    registerFactory('SizedBox', (node) => SizedBox(
          width: node.width,
          height: node.height,
          child: node.children.isNotEmpty ? node.firstChild : null,
        ));

    registerFactory('SingleChildScrollView', (node) =>
        SingleChildScrollView(
          padding: DuiUtils.parsePadding(node.props['padding']),
          child: node.firstChild,
        ));

    // ---- 文本类 ----
    registerFactory('Text', (node) {
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

    registerFactory('SelectableText', (node) {
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

    // ---- 输入框 (带双向绑定) ----
    registerFactory('TextField', (node) {
      final currentVal =
          node.ref != null ? (state.get(node.ref!)?.toString() ?? '') : '';
      return _BoundTextField(
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
    });

    // ---- 按钮类 ----
    registerFactory('FilledButton', (node) {
      final label = state.interpolate(node.props['text']?.toString() ?? '');
      final iconStr = node.props['icon']?.toString();
      void onPressed() =>
          eventHandler.handleEvent(node.events['onPressed']);
      return iconStr != null
          ? FilledButton.icon(
              icon: Icon(DuiUtils.parseIcon(iconStr)),
              label: Text(label),
              onPressed: onPressed,
            )
          : FilledButton(onPressed: onPressed, child: Text(label));
    });

    registerFactory('OutlinedButton', (node) {
      final label = state.interpolate(node.props['text']?.toString() ?? '');
      final iconStr = node.props['icon']?.toString();
      void onPressed() =>
          eventHandler.handleEvent(node.events['onPressed']);
      return iconStr != null
          ? OutlinedButton.icon(
              icon: Icon(DuiUtils.parseIcon(iconStr)),
              label: Text(label),
              onPressed: onPressed,
            )
          : OutlinedButton(onPressed: onPressed, child: Text(label));
    });

    registerFactory('IconButton', (node) => IconButton(
          icon: Icon(DuiUtils.parseIcon(node.props['icon']?.toString())),
          tooltip: node.props['tooltip']?.toString(),
          onPressed: () =>
              eventHandler.handleEvent(node.events['onPressed']),
        ));

    // ---- 容器类 ----
    registerFactory('Card', (node) => Card(
          elevation: DuiUtils.tryDouble(node.props['elevation']) ?? 0,
          child: node.firstChild,
        ));

    registerFactory('Container', (node) {
      final borderRadiusVal = DuiUtils.tryDouble(node.props['borderRadius']);
      final colorRaw = node.props['color']?.toString() ?? '';
      final keys = DuiState.extractKeys(colorRaw);

      Widget buildContainer() => Container(
            padding: DuiUtils.parsePadding(node.props['padding']),
            width: node.width,
            height: node.height,
            decoration: BoxDecoration(
              // color 支持渲染期状态插值 (如颜色工具的动态色块)
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

    // ---- 列表类 ----
    registerFactory('ListView', (node) => ListView(
          shrinkWrap: DuiUtils.tryBool(node.props['shrinkWrap']),
          padding: DuiUtils.parsePadding(node.props['padding']),
          children: node.childrenWidgets,
        ));

    registerFactory('ListTile', (node) => ListTile(
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

    // ---- 图片显示 (从插件本地沙箱目录加载) ----
    registerFactory('Image', _imageWidget);

    // ---- 像素网格 (状态 0/1 位图逐格填充, 如二维码矩阵) ----
    registerFactory('PixelGrid', (node) {
      // data/cols/cellSize 均为渲染期取值, 支持从状态插值
      final data = state.interpolate(node.props['data']?.toString() ?? '');
      final cols =
          DuiUtils.tryInt(state.interpolate(node.props['cols']?.toString() ?? ''));
      final cellSize = DuiUtils.tryDouble(
          state.interpolate(node.props['cellSize']?.toString() ?? ''));
      return DuiPixelGrid(
        data: data,
        cols: cols ?? 0,
        cellSize: cellSize ?? 4.0,
        darkColor:
            DuiUtils.parseColor(node.props['darkColor']) ?? const Color(0xFF000000),
        lightColor: DuiUtils.parseColor(node.props['lightColor']) ??
            const Color(0xFFFFFFFF),
      );
    });

    // ---- 流式布局 (Wrap) ----
    registerFactory('Wrap', (node) => Wrap(
          spacing: DuiUtils.tryDouble(node.props['spacing']) ?? 0.0,
          runSpacing: DuiUtils.tryDouble(node.props['runSpacing']) ?? 0.0,
          alignment: _parseWrapAlignment(node.props['alignment']?.toString()),
          children: node.childrenWidgets,
        ));

    // ---- 分割线 (Divider) ----
    registerFactory('Divider', (node) => Divider(
          height: DuiUtils.tryDouble(node.props['height']),
          thickness: DuiUtils.tryDouble(node.props['thickness']),
          color: DuiUtils.parseColor(
              state.interpolate(node.props['color']?.toString() ?? '')),
        ));

    // ---- 进度条 (ProgressBar) ----
    registerFactory('ProgressBar', (node) {
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
    registerFactory('Switch', (node) {
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
    registerFactory('Slider', (node) {
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
    registerFactory('Dropdown', (node) {
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

      return _DuiTabs(
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
    registerFactory('Tabs', buildTabs);
    registerFactory('TabBar', buildTabs);

    // ---- Markdown 渲染组件 (MarkdownView / Markdown) ----
    Widget buildMarkdown(DuiNodeContext node) {
      final rawText = node.props['text']?.toString() ??
          node.props['data']?.toString() ??
          '';
      final selectable =
          DuiUtils.tryBool(node.props['selectable'], fallback: true);
      final keys = DuiState.extractKeys(rawText);

      Widget renderMd() => DuiMarkdownView(
            data: state.interpolate(rawText),
            selectable: selectable,
          );

      if (keys.isEmpty) return renderMd();
      return ListenableBuilder(
        listenable: state.listenableForKeys(keys),
        builder: (_, __) => renderMd(),
      );
    }
    registerFactory('MarkdownView', buildMarkdown);
    registerFactory('Markdown', buildMarkdown);
  }

  /// 防御式 Map 转换：不同来源的 JSON 数据可能解析为 `Map<dynamic, dynamic>`，
  /// 直接强转 `Map<String, dynamic>` 会抛 TypeError 使插件页面崩溃
  static Map<String, dynamic> _asMap(Object? raw) {
    if (raw is Map) {
      return {
        for (final entry in raw.entries)
          if (entry.key is String) entry.key as String: entry.value,
      };
    }
    return const {};
  }

  Widget _imageWidget(DuiNodeContext node) {
    final src = node.props['src']?.toString() ?? '';
    final rootDir = node.renderer.pluginRootDir;
    // 路径穿越防御：src 必须归一化后仍严格位于插件沙箱根目录之内，
    // 否则 (例如 "../../etc/passwd") 直接拒绝渲染
    if (rootDir == null ||
        src.isEmpty ||
        !SandboxPath.isSafeSubpath(rootDir.path, src)) {
      return const SizedBox.shrink();
    }
    return Image.file(
      File('${rootDir.path}/$src'),
      width: node.width,
      height: node.height,
      fit: BoxFit.contain,
      cacheWidth: 256,
      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
    );
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

  WrapAlignment _parseWrapAlignment(String? val) {
    switch (val) {
      case 'center': return WrapAlignment.center;
      case 'end': return WrapAlignment.end;
      case 'spaceBetween': return WrapAlignment.spaceBetween;
      case 'spaceAround': return WrapAlignment.spaceAround;
      case 'spaceEvenly': return WrapAlignment.spaceEvenly;
      default: return WrapAlignment.start;
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
      final oldSelection = _controller.selection;
      _controller.text = widget.initialText;
      // 保持光标位置（限制在合法文本区间内），防止外部状态更新时光标跳跃至末尾或丢失
      final newOffset =
          oldSelection.baseOffset.clamp(0, widget.initialText.length);
      _controller.selection = TextSelection.collapsed(offset: newOffset);
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

class _DuiTabs extends StatefulWidget {
  final List<String> tabTitles;
  final List<Widget> children;
  final int initialIndex;
  final String? refKey;
  final DuiState state;
  final ValueChanged<int>? onChanged;

  const _DuiTabs({
    required this.tabTitles,
    required this.children,
    this.initialIndex = 0,
    this.refKey,
    required this.state,
    this.onChanged,
  });

  @override
  State<_DuiTabs> createState() => _DuiTabsState();
}

class _DuiTabsState extends State<_DuiTabs> {
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
  void didUpdateWidget(covariant _DuiTabs oldWidget) {
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

