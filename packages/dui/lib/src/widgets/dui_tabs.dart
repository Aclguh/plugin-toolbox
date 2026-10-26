import 'package:flutter/material.dart';

import '../dui_state.dart';

/// 动态界面的标签页切换分段容器
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
    _currentIndex = widget.initialIndex;
    if (widget.refKey != null) {
      final current = widget.state.get(widget.refKey!);
      if (current is int && current >= 0 && current < widget.children.length) {
        _currentIndex = current;
      }
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
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
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
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutCubic,
                        padding: const EdgeInsets.symmetric(vertical: 9),
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
