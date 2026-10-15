import 'dart:convert';
import 'package:flutter/material.dart';

/// 动态 UI (DUI) 树形折叠组件。
///
/// 支持任意 JSON/Map/List 结构化数据或显式 TreeNode 树展示，
/// 提供层级缩进、节点折叠/展开、类型图标识别与点击事件回调。
class DuiTreeView extends StatefulWidget {
  final dynamic data;
  final bool expandAll;
  final bool selectable;
  final bool showIcons;
  final double indent;
  final double? height;
  final void Function(Map<String, dynamic> nodeInfo)? onNodeClick;

  const DuiTreeView({
    super.key,
    required this.data,
    this.expandAll = false,
    this.selectable = true,
    this.showIcons = true,
    this.indent = 16.0,
    this.height,
    this.onNodeClick,
  });

  @override
  State<DuiTreeView> createState() => _DuiTreeViewState();
}

class _DuiTreeViewState extends State<DuiTreeView> {
  final Set<String> _expandedPaths = {};
  String? _selectedPath;

  @override
  void initState() {
    super.initState();
    _initExpandedState();
  }

  @override
  void didUpdateWidget(covariant DuiTreeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.expandAll != oldWidget.expandAll ||
        widget.data != oldWidget.data) {
      _initExpandedState();
    }
  }

  void _initExpandedState() {
    if (widget.expandAll) {
      final roots = _parseNodes(widget.data);
      for (final r in roots) {
        _collectAllContainerPaths(r, _expandedPaths);
      }
    }
  }

  void _collectAllContainerPaths(_TreeNode node, Set<String> paths) {
    if (node.children.isNotEmpty) {
      paths.add(node.path);
      for (final c in node.children) {
        _collectAllContainerPaths(c, paths);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final backgroundColor =
        isDark ? const Color(0xFF141926) : const Color(0xFFF8FAFC);
    final borderColor =
        isDark ? const Color(0xFF2D3748) : const Color(0xFFE2E8F0);

    final roots = _parseNodes(widget.data);

    Widget content;
    if (roots.isEmpty) {
      content = Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            '无树形数据',
            style: TextStyle(color: theme.colorScheme.outline),
          ),
        ),
      );
    } else {
      content = ListView(
        shrinkWrap: widget.height == null,
        physics: widget.height == null
            ? const NeverScrollableScrollPhysics()
            : const ClampingScrollPhysics(),
        children: [
          for (final rootNode in roots) ..._buildNodeRows(context, rootNode, 0),
        ],
      );
    }

    Widget root = Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: content,
    );

    if (widget.height != null) {
      root = SizedBox(height: widget.height, child: root);
    }

    return root;
  }

  List<Widget> _buildNodeRows(BuildContext context, _TreeNode node, int depth) {
    final hasChildren = node.children.isNotEmpty;
    final isExpanded = _expandedPaths.contains(node.path);
    final isSelected = _selectedPath == node.path;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final selectedBg =
        isDark ? const Color(0x33788CFF) : const Color(0x22788CFF);
    final hoverColor =
        isDark ? const Color(0x1AFFFFFF) : const Color(0x0A000000);

    final row = InkWell(
      onTap: () {
        if (hasChildren) {
          setState(() {
            if (isExpanded) {
              _expandedPaths.remove(node.path);
            } else {
              _expandedPaths.add(node.path);
            }
          });
        }
        if (widget.selectable) {
          setState(() {
            _selectedPath = node.path;
          });
        }
        widget.onNodeClick?.call({
          'path': node.path,
          'label': node.label,
          'value': node.rawValue,
          'isLeaf': !hasChildren,
        });
      },
      hoverColor: hoverColor,
      child: Container(
        color: isSelected ? selectedBg : Colors.transparent,
        padding: EdgeInsets.only(
          left: 8.0 + depth * widget.indent,
          right: 8.0,
          top: 4.0,
          bottom: 4.0,
        ),
        child: Row(
          children: [
            // 折叠/展开图标
            SizedBox(
              width: 20,
              height: 20,
              child: hasChildren
                  ? Icon(
                      isExpanded
                          ? Icons.keyboard_arrow_down
                          : Icons.chevron_right,
                      size: 16,
                      color: isDark
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF64748B),
                    )
                  : const SizedBox.shrink(),
            ),
            const SizedBox(width: 4),
            // 类型图标
            if (widget.showIcons) ...[
              Icon(
                _getIconForNode(node, isExpanded),
                size: 15,
                color: _getIconColor(node, isDark),
              ),
              const SizedBox(width: 6),
            ],
            // 节点名称
            Text(
              node.label,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12.5,
                fontWeight: hasChildren ? FontWeight.w600 : FontWeight.normal,
                color: isSelected
                    ? (isDark
                        ? const Color(0xFFB4C9FF)
                        : theme.colorScheme.primary)
                    : (isDark
                        ? const Color(0xFFE2E8F0)
                        : const Color(0xFF1E293B)),
              ),
            ),
            // 叶子节点展示具体值
            if (!hasChildren && node.displayValue != null) ...[
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  node.displayValue!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12.0,
                    color: _getValueColor(node.valueType, isDark),
                  ),
                ),
              ),
            ] else if (hasChildren && node.childrenCount > 0) ...[
              const SizedBox(width: 6),
              Text(
                '(${node.childrenCount})',
                style: TextStyle(
                  fontSize: 11.0,
                  color: isDark
                      ? const Color(0xFF64748B)
                      : const Color(0xFF94A3B8),
                ),
              ),
            ],
          ],
        ),
      ),
    );

    final widgets = <Widget>[row];
    if (hasChildren && isExpanded) {
      for (final child in node.children) {
        widgets.addAll(_buildNodeRows(context, child, depth + 1));
      }
    }
    return widgets;
  }

  static IconData _getIconForNode(_TreeNode node, bool isExpanded) {
    if (node.children.isNotEmpty) {
      return isExpanded ? Icons.folder_open : Icons.folder;
    }
    switch (node.valueType) {
      case _NodeType.string:
        return Icons.text_snippet_outlined;
      case _NodeType.number:
        return Icons.tag;
      case _NodeType.boolean:
        return Icons.check_circle_outline;
      case _NodeType.nil:
        return Icons.remove_circle_outline;
      default:
        return Icons.circle;
    }
  }

  static Color _getIconColor(_TreeNode node, bool isDark) {
    if (node.children.isNotEmpty) {
      return isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706); // 琥珀黄
    }
    switch (node.valueType) {
      case _NodeType.string:
        return isDark ? const Color(0xFF4ADE80) : const Color(0xFF16A34A);
      case _NodeType.number:
        return isDark ? const Color(0xFFFB923C) : const Color(0xFFEA580C);
      case _NodeType.boolean:
        return isDark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB);
      default:
        return isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    }
  }

  static Color _getValueColor(_NodeType type, bool isDark) {
    switch (type) {
      case _NodeType.string:
        return isDark ? const Color(0xFF86EFAC) : const Color(0xFF15803D);
      case _NodeType.number:
        return isDark ? const Color(0xFFFDBA74) : const Color(0xFFC2410C);
      case _NodeType.boolean:
        return isDark ? const Color(0xFF93C5FD) : const Color(0xFF1D4ED8);
      case _NodeType.nil:
        return isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626);
      default:
        return isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    }
  }

  static List<_TreeNode> _parseNodes(dynamic rawData) {
    if (rawData == null) return [];

    dynamic parsed = rawData;
    if (rawData is String) {
      final trimmed = rawData.trim();
      if ((trimmed.startsWith('{') && trimmed.endsWith('}')) ||
          (trimmed.startsWith('[') && trimmed.endsWith(']'))) {
        try {
          parsed = jsonDecode(trimmed);
        } catch (_) {
          return [
            _TreeNode(path: 'root', label: trimmed, valueType: _NodeType.string)
          ];
        }
      } else {
        return [
          _TreeNode(path: 'root', label: trimmed, valueType: _NodeType.string)
        ];
      }
    }

    if (parsed is List) {
      // 检查是否显式 TreeNode 结构
      final isExplicitTree = parsed.isNotEmpty &&
          parsed.first is Map &&
          (parsed.first as Map).containsKey('label');

      if (isExplicitTree) {
        return [
          for (var i = 0; i < parsed.length; i++)
            _parseExplicitNode(parsed[i] as Map, 'node_$i'),
        ];
      }

      // 泛型 List
      final roots = <_TreeNode>[];
      for (var i = 0; i < parsed.length; i++) {
        roots.add(_parseGenericValue('[$i]', parsed[i], 'item_$i'));
      }
      return roots;
    }

    if (parsed is Map) {
      final roots = <_TreeNode>[];
      parsed.forEach((key, val) {
        roots.add(_parseGenericValue(key.toString(), val, 'key_$key'));
      });
      return roots;
    }

    return [
      _TreeNode(
          path: 'root',
          label: parsed.toString(),
          valueType: _NodeType.primitive)
    ];
  }

  static _TreeNode _parseExplicitNode(Map raw, String currentPath) {
    final label = raw['label']?.toString() ?? 'node';
    final value = raw['value'];
    final rawChildren = raw['children'];

    final children = <_TreeNode>[];
    if (rawChildren is List) {
      for (var i = 0; i < rawChildren.length; i++) {
        if (rawChildren[i] is Map) {
          children.add(
              _parseExplicitNode(rawChildren[i] as Map, '$currentPath/$i'));
        }
      }
    }

    return _TreeNode(
      path: currentPath,
      label: label,
      displayValue: value?.toString(),
      rawValue: value,
      children: children,
      valueType: _inferType(value),
    );
  }

  static _TreeNode _parseGenericValue(String label, dynamic val, String path) {
    if (val is Map) {
      final children = <_TreeNode>[];
      val.forEach((k, v) {
        children.add(_parseGenericValue(k.toString(), v, '$path/$k'));
      });
      return _TreeNode(
        path: path,
        label: label,
        children: children,
        childrenCount: val.length,
        valueType: _NodeType.container,
      );
    } else if (val is List) {
      final children = <_TreeNode>[];
      for (var i = 0; i < val.length; i++) {
        children.add(_parseGenericValue('[$i]', val[i], '$path/$i'));
      }
      return _TreeNode(
        path: path,
        label: label,
        children: children,
        childrenCount: val.length,
        valueType: _NodeType.container,
      );
    } else {
      String display;
      if (val is String) {
        display = '"$val"';
      } else {
        display = val?.toString() ?? 'null';
      }
      return _TreeNode(
        path: path,
        label: label,
        displayValue: display,
        rawValue: val,
        valueType: _inferType(val),
      );
    }
  }

  static _NodeType _inferType(dynamic val) {
    if (val == null) return _NodeType.nil;
    if (val is bool) return _NodeType.boolean;
    if (val is num) return _NodeType.number;
    if (val is String) return _NodeType.string;
    return _NodeType.primitive;
  }
}

enum _NodeType { container, string, number, boolean, nil, primitive }

class _TreeNode {
  final String path;
  final String label;
  final String? displayValue;
  final dynamic rawValue;
  final List<_TreeNode> children;
  final int childrenCount;
  final _NodeType valueType;

  _TreeNode({
    required this.path,
    required this.label,
    this.displayValue,
    this.rawValue,
    this.children = const [],
    this.childrenCount = 0,
    this.valueType = _NodeType.primitive,
  });
}
