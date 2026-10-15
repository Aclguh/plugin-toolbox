import 'package:flutter/material.dart';

import 'dui_utils.dart';

/// 动态 UI (DUI) 颜色拾取组件。
///
/// 支持调色板预设色块、RGB/RGBA 滑块精细调节、Hex 文本输入与双向绑定。
class DuiColorPicker extends StatefulWidget {
  final String value;
  final bool showPalette;
  final List<String>? palette;
  final bool showSliders;
  final bool showAlpha;
  final bool showInput;
  final double? height;
  final ValueChanged<String>? onChanged;

  const DuiColorPicker({
    super.key,
    this.value = '#788CFF',
    this.showPalette = true,
    this.palette,
    this.showSliders = true,
    this.showAlpha = false,
    this.showInput = true,
    this.height,
    this.onChanged,
  });

  @override
  State<DuiColorPicker> createState() => _DuiColorPickerState();
}

class _DuiColorPickerState extends State<DuiColorPicker> {
  late Color _currentColor;
  late TextEditingController _hexController;

  static const List<String> _defaultPalette = [
    '#26366A', // 工具箱藏蓝品牌色
    '#788CFF', // 靛青主交互色
    '#31D9D0', // 薄荷青辅助色
    '#FF9D72', // 珊瑚粉
    '#F44336', // 红色
    '#E91E63', // 粉红
    '#9C27B0', // 紫色
    '#673AB7', // 深紫
    '#3F51B5', // 靛蓝
    '#2196F3', // 蓝色
    '#00BCD4', // 青色
    '#4CAF50', // 绿色
    '#8BC34A', // 浅绿
    '#FFEB3B', // 黄色
    '#FF9800', // 橙色
    '#607D8B', // 蓝灰
    '#FFFFFF', // 白
    '#000000', // 黑
  ];

  @override
  void initState() {
    super.initState();
    _currentColor = _parseColor(widget.value);
    _hexController = TextEditingController(text: _toHex(_currentColor, widget.showAlpha));
  }

  @override
  void didUpdateWidget(covariant DuiColorPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      final parsed = _parseColor(widget.value);
      if (parsed.toARGB32() != _currentColor.toARGB32()) {
        _currentColor = parsed;
        _hexController.text = _toHex(_currentColor, widget.showAlpha);
      }
    }
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  Color _parseColor(String val) {
    final c = DuiUtils.parseColor(val);
    return c ?? const Color(0xFF788CFF);
  }

  static String _toHex(Color color, bool includeAlpha) {
    final a = (color.a * 255).round().clamp(0, 255);
    final r = (color.r * 255).round().clamp(0, 255);
    final g = (color.g * 255).round().clamp(0, 255);
    final b = (color.b * 255).round().clamp(0, 255);

    final rHex = r.toRadixString(16).padLeft(2, '0').toUpperCase();
    final gHex = g.toRadixString(16).padLeft(2, '0').toUpperCase();
    final bHex = b.toRadixString(16).padLeft(2, '0').toUpperCase();

    if (includeAlpha) {
      final aHex = a.toRadixString(16).padLeft(2, '0').toUpperCase();
      return '#$aHex$rHex$gHex$bHex';
    }
    return '#$rHex$gHex$bHex';
  }

  void _updateColor(Color newColor, {bool syncText = true}) {
    setState(() {
      _currentColor = newColor;
      if (syncText) {
        _hexController.text = _toHex(newColor, widget.showAlpha);
      }
    });
    widget.onChanged?.call(_toHex(newColor, widget.showAlpha));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final backgroundColor = isDark ? const Color(0xFF141926) : const Color(0xFFF8FAFC);
    final borderColor = isDark ? const Color(0xFF2D3748) : const Color(0xFFE2E8F0);

    final paletteColors = widget.palette ?? _defaultPalette;

    final r = (_currentColor.r * 255).round().clamp(0, 255);
    final g = (_currentColor.g * 255).round().clamp(0, 255);
    final b = (_currentColor.b * 255).round().clamp(0, 255);
    final a = (_currentColor.a * 255).round().clamp(0, 255);

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 顶部色彩预览条与 Hex / RGB 信息
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E2638) : const Color(0xFFEDF2F7),
            border: Border(bottom: BorderSide(color: borderColor)),
          ),
          child: Row(
            children: [
              // 颜色预览圆块
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _currentColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white24, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: _currentColor.withValues(alpha: 0.4),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              // 色彩值文字
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _toHex(_currentColor, widget.showAlpha),
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.showAlpha
                          ? 'rgba($r, $g, $b, ${(a / 255).toStringAsFixed(2)})'
                          : 'rgb($r, $g, $b)',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              // Hex 输入框
              if (widget.showInput)
                SizedBox(
                  width: 100,
                  height: 36,
                  child: TextField(
                    controller: _hexController,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                      isDense: true,
                    ),
                    onChanged: (text) {
                      final hex = text.trim();
                      if (hex.length >= 4) {
                        final parsed = DuiUtils.parseColor(hex);
                        if (parsed != null) {
                          _updateColor(parsed, syncText: false);
                        }
                      }
                    },
                  ),
                ),
            ],
          ),
        ),

        // 预设调色板
        if (widget.showPalette) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Text(
              '预设调色盘',
              style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final hexStr in paletteColors)
                  _buildPaletteSwatch(hexStr, isDark),
              ],
            ),
          ),
        ],

        // RGB 滑块调节
        if (widget.showSliders) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Text(
              '色彩通道微调',
              style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          _buildSliderRow('R', r, Colors.red, (val) {
            _updateColor(Color.fromARGB(a, val.round(), g, b));
          }),
          _buildSliderRow('G', g, Colors.green, (val) {
            _updateColor(Color.fromARGB(a, r, val.round(), b));
          }),
          _buildSliderRow('B', b, Colors.blue, (val) {
            _updateColor(Color.fromARGB(a, r, g, val.round()));
          }),
          if (widget.showAlpha)
            _buildSliderRow('A', a, Colors.grey, (val) {
              _updateColor(Color.fromARGB(val.round(), r, g, b));
            }),
        ],
        const SizedBox(height: 8),
      ],
    );

    Widget root = Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      clipBehavior: Clip.antiAlias,
      child: widget.height == null ? content : SingleChildScrollView(child: content),
    );

    if (widget.height != null) {
      root = SizedBox(height: widget.height, child: root);
    }

    return root;
  }

  Widget _buildPaletteSwatch(String hexStr, bool isDark) {
    final swatchColor = DuiUtils.parseColor(hexStr) ?? Colors.transparent;
    final isSelected = swatchColor.toARGB32() == _currentColor.toARGB32();

    return GestureDetector(
      onTap: () => _updateColor(swatchColor),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: swatchColor,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? Colors.white : (isDark ? Colors.white12 : Colors.black12),
            width: isSelected ? 2.5 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: swatchColor.withValues(alpha: 0.6),
                    blurRadius: 6,
                  )
                ]
              : null,
        ),
        child: isSelected
            ? Icon(
                Icons.check,
                size: 14,
                color: swatchColor.computeLuminance() > 0.5 ? Colors.black : Colors.white,
              )
            : null,
      ),
    );
  }

  Widget _buildSliderRow(
    String label,
    int value,
    Color activeColor,
    ValueChanged<double> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
                color: activeColor,
              ),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: activeColor,
                thumbColor: activeColor,
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              ),
              child: Slider(
                value: value.toDouble(),
                min: 0,
                max: 255,
                onChanged: onChanged,
              ),
            ),
          ),
          SizedBox(
            width: 32,
            child: Text(
              '$value',
              textAlign: TextAlign.right,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}
