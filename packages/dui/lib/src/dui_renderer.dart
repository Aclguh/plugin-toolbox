import 'dart:io';

import 'package:flutter/material.dart';

import 'dui_error_boundary.dart';
import 'dui_event_handler.dart';
import 'dui_state.dart';
import 'dui_utils.dart';
import 'factories/data_view_factories.dart';
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

/// AST 节点的装载期预编译描述。
///
/// 一份 AST (ui.json 解析产物) 在页面生命周期内是不可变的静态结构，
/// 但每次 build 都会为每个节点重跑 visible 键正则提取与防御式 Map 转换，
/// 且任一祖先重建都会沿 childAt 递归放大该开销；因此在首次访问时
/// 将 type / visible 绑定键 / props / children / events 一次提取并缓存。
class _CompiledNode {
  final String type;
  final dynamic visibleExpr;
  final Set<String> visibleKeys;
  final Map<String, dynamic> props;
  final List<Map<String, dynamic>> children;
  final Map<String, dynamic> events;
  final String? ref;

  const _CompiledNode({
    required this.type,
    required this.visibleExpr,
    required this.visibleKeys,
    required this.props,
    required this.children,
    required this.events,
    required this.ref,
  });
}

/// 声明式 UI (DUI) 核心渲染引擎。
///
/// 负责维护组件工厂字典、下沉局部精准刷新与递归解析 JSON AST 节点树。
class DuiRenderer {
  final DuiState state;
  final DuiEventHandler eventHandler;
  final Directory? pluginRootDir;

  final Map<String, DuiWidgetFactory> _factories = {};

  /// 以节点 Map 实例身份为键的预编译缓存 (Expando 弱引用, AST 释放后自动回收)
  final Expando<_CompiledNode> _compiledNodes = Expando('_CompiledNodeCache');

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
    final compiled = _compile(node);

    // 条件可见性含响应式绑定：仅在本节点边界订阅对应键，
    // 键变化只触发该节点子树的取舍，不波及兄弟与祖先
    if (compiled.visibleKeys.isNotEmpty) {
      return ListenableBuilder(
        listenable: state.listenableForKeys(compiled.visibleKeys),
        builder: (ctx, _) {
          if (!state.evaluateVisible(compiled.visibleExpr)) {
            return const SizedBox.shrink();
          }
          return _buildNodeContent(ctx, compiled);
        },
      );
    }

    if (!state.evaluateVisible(compiled.visibleExpr)) {
      return const SizedBox.shrink();
    }

    return _buildNodeContent(context, compiled);
  }

  /// 装载期预编译：同一节点实例只提取一次 type 与绑定键
  _CompiledNode _compile(Map<String, dynamic> node) {
    final cached = _compiledNodes[node];
    if (cached != null) return cached;

    final visibleExpr = node['visible'];
    final compiled = _CompiledNode(
      type: node['type']?.toString() ?? 'Container',
      visibleExpr: visibleExpr,
      visibleKeys: visibleExpr != null
          ? DuiState.extractKeys(visibleExpr.toString())
          : const <String>{},
      props: _asMap(node['props']),
      children: [
        for (final c in node['children'] as List<dynamic>? ?? const [])
          if (c is Map) _asMap(c),
      ],
      events: _asMap(node['events']),
      ref: node['ref']?.toString(),
    );
    _compiledNodes[node] = compiled;
    return compiled;
  }

  Widget _buildNodeContent(BuildContext context, _CompiledNode compiled) {
    final factory = _factories[compiled.type];
    if (factory == null) {
      return const SizedBox.shrink();
    }

    return DuiNodeErrorBoundary(
      nodeType: compiled.type,
      builder: () => factory(
        DuiNodeContext(
          context: context,
          renderer: this,
          props: compiled.props,
          children: compiled.children,
          events: compiled.events,
          ref: compiled.ref,
        ),
      ),
      fallback: (error, stackTrace) => DuiErrorPlaceholder(
        type: compiled.type,
        error: error,
        stackTrace: stackTrace,
      ),
    );
  }

  void _registerBuiltinFactories() {
    registerLayoutFactories(this);
    registerTextFactories(this);
    registerInputFactories(this);
    registerMediaFactories(this);
    registerDataViewFactories(this);
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
