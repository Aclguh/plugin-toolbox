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
  final DuiScopeContext? scope;
  final Set<String> textKeys;

  const DuiNodeContext({
    required this.context,
    required this.renderer,
    required this.props,
    required this.children,
    required this.events,
    required this.ref,
    this.scope,
    this.textKeys = const {},
  });

  /// 构建第 [index] 个子节点（继承当前作用域环境）
  Widget childAt(int index) =>
      renderer.buildWidget(context, children[index], scope: scope);

  /// 首个子节点；无子节点时返回占位
  Widget get firstChild =>
      children.isNotEmpty ? childAt(0) : const SizedBox.shrink();

  /// 构建全部子节点
  List<Widget> get childrenWidgets =>
      [for (var i = 0; i < children.length; i++) childAt(i)];

  /// 解析当前作用域或全局状态的文本插值
  String interpolate(String? template) {
    if (template == null) return '';
    return renderer.state.interpolate(template, scope);
  }

  /// 派发组件事件（继承当前作用域环境变量）
  void handleEvent(Map? eventDef, [dynamic payload]) {
    renderer.eventHandler.handleEvent(eventDef, payload, scope);
  }

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
/// 将 type / visible 绑定键 / textKeys / props / children / events 一次提取并缓存。
class _CompiledNode {
  final String type;
  final dynamic visibleExpr;
  final DuiParsedExpression? visibleAst;
  final Set<String> visibleKeys;
  final Set<String> textKeys;
  final Map<String, dynamic> props;
  final List<Map<String, dynamic>> children;
  final Map<String, dynamic> events;
  final String? ref;

  const _CompiledNode({
    required this.type,
    required this.visibleExpr,
    this.visibleAst,
    required this.visibleKeys,
    required this.textKeys,
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
  Widget build(BuildContext context, Map<String, dynamic> rootNode,
      {DuiScopeContext? scope}) {
    return buildWidget(context, rootNode, scope: scope);
  }

  /// 将 JSON 节点递归转换为 Flutter Widget
  Widget buildWidget(BuildContext context, Map<String, dynamic> node,
      {DuiScopeContext? scope}) {
    try {
      final compiled = _compile(node);

      // 条件可见性含响应式绑定：仅在本节点边界订阅对应键，
      // 键变化只触发该节点子树的取舍，不波及兄弟与祖先
      if (compiled.visibleKeys.isNotEmpty) {
        return ListenableBuilder(
          listenable: state.listenableForKeys(compiled.visibleKeys),
          builder: (ctx, _) {
            if (!state.evaluateVisible(compiled.visibleExpr, scope)) {
              return const SizedBox.shrink();
            }
            return _buildNodeContent(ctx, compiled, scope);
          },
        );
      }

      if (!state.evaluateVisible(compiled.visibleExpr, scope)) {
        return const SizedBox.shrink();
      }

      return _buildNodeContent(context, compiled, scope);
    } catch (e, st) {
      return DuiErrorPlaceholder(
        type: node['type']?.toString() ?? 'Unknown',
        error: e,
        stackTrace: st,
      );
    }
  }

  /// 装载期预编译：同一节点实例只提取一次 type 与绑定键
  _CompiledNode _compile(Map<String, dynamic> node) {
    final cached = _compiledNodes[node];
    if (cached != null) return cached;

    final visibleExpr = node['visible'];
    final rawChildren = node['children'];
    final props = _asMap(node['props']);
    final rawText = props['text']?.toString();
    final compiled = _CompiledNode(
      type: node['type']?.toString() ?? 'Container',
      visibleExpr: visibleExpr,
      visibleAst: visibleExpr != null
          ? DuiExpressionEvaluator.compile(visibleExpr.toString())
          : null,
      visibleKeys: visibleExpr != null
          ? DuiState.extractKeys(visibleExpr.toString())
          : const <String>{},
      textKeys:
          rawText != null ? DuiState.extractKeys(rawText) : const <String>{},
      props: props,
      children: _compileChildren(node, rawChildren),
      events: _asMap(node['events']),
      ref: node['ref']?.toString(),
    );
    _compiledNodes[node] = compiled;
    return compiled;
  }

  Widget _buildNodeContent(
      BuildContext context, _CompiledNode compiled, DuiScopeContext? scope) {
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
          scope: scope,
          textKeys: compiled.textKeys,
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

  /// 子节点编译。
  ///
  /// 规范写法是 `children: [...]`，但生态中不少手写插件会写成单子节点
  /// `child: {...}`（与部分声明式框架一致）。这里把 `child` 作为
  /// 单元素 `children` 的别名兼容，避免整页静默渲染为空白。
  static List<Map<String, dynamic>> _compileChildren(
    Map<String, dynamic> node,
    Object? rawChildren,
  ) {
    if (rawChildren is List) {
      return [
        for (final c in rawChildren)
          if (c is Map) _asMap(c),
      ];
    }
    final single = node['child'];
    if (single is Map) {
      return [_asMap(single)];
    }
    return const <Map<String, dynamic>>[];
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
