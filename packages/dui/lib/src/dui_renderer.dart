import 'dart:io';

import 'package:flutter/material.dart';

import 'dui_event_handler.dart';
import 'dui_state.dart';
import 'dui_utils.dart';
import 'factories/input_factories.dart';
import 'factories/layout_factories.dart';
import 'factories/media_factories.dart';
import 'factories/text_factories.dart';

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
  List<Widget> get childrenWidgets =>
      [for (var i = 0; i < children.length; i++) childAt(i)];

  // ---- 常用安全属性读取快捷方式 ----
  double? get width => DuiUtils.tryDouble(props['width']);
  double? get height => DuiUtils.tryDouble(props['height']);
}

typedef DuiWidgetFactory = Widget Function(DuiNodeContext node);

/// 声明式 UI (DUI) 核心渲染引擎。
///
/// 负责维护组件工厂字典、下沉局部精准刷新与递归解析 JSON AST 节点树。
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

  /// 构建声明式组件树根节点（下沉局部精准刷新，消除顶层全局全量重建风暴）
  Widget build(BuildContext context, Map<String, dynamic> rootNode) {
    return buildWidget(context, rootNode);
  }

  /// 将 JSON 节点递归转换为 Flutter Widget
  Widget buildWidget(BuildContext context, Map<String, dynamic> node) {
    // 1. 检查条件可见性（包含局部响应式绑定）
    final visibleExpr = node['visible'];
    final visibleKeys = visibleExpr != null
        ? DuiState.extractKeys(visibleExpr.toString())
        : const <String>{};

    if (visibleKeys.isNotEmpty) {
      return ListenableBuilder(
        listenable: state.listenableForKeys(visibleKeys),
        builder: (ctx, _) {
          if (!state.evaluateVisible(visibleExpr)) {
            return const SizedBox.shrink();
          }
          return _buildNodeContent(ctx, node);
        },
      );
    }

    if (!state.evaluateVisible(visibleExpr)) {
      return const SizedBox.shrink();
    }

    return _buildNodeContent(context, node);
  }

  Widget _buildNodeContent(BuildContext context, Map<String, dynamic> node) {
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
    registerLayoutFactories(this);
    registerTextFactories(this);
    registerInputFactories(this);
    registerMediaFactories(this);
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
}
