import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'dui_utils.dart';

/// 声明式 DUI 图表组件：支持轻量折线图 (line) 与柱状图 (bar)。
///
/// 纯 Dart CustomPainter 绘制，无第三方依赖，响应式适配暗色与亮色主题。
class DuiChart extends StatelessWidget {
  final String chartType;
  final dynamic data;
  final dynamic labels;
  final double? width;
  final double height;
  final Color? color;
  final Color? secondaryColor;
  final Color? backgroundColor;
  final double? minY;
  final double? maxY;
  final bool showGrid;
  final bool showLabels;
  final bool showDots;
  final bool filled;
  final double strokeWidth;
  final double? barWidth;

  const DuiChart({
    super.key,
    this.chartType = 'line',
    required this.data,
    this.labels,
    this.width,
    this.height = 200.0,
    this.color,
    this.secondaryColor,
    this.backgroundColor,
    this.minY,
    this.maxY,
    this.showGrid = true,
    this.showLabels = true,
    this.showDots = true,
    this.filled = true,
    this.strokeWidth = 2.5,
    this.barWidth,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = color ?? theme.colorScheme.primary;
    final secColor = secondaryColor ?? primaryColor.withValues(alpha: 0.2);
    final gridColor = theme.dividerColor.withValues(alpha: 0.15);
    final labelColor = theme.colorScheme.onSurface.withValues(alpha: 0.6);

    final values = _parseValues(data);
    final parsedLabels = _parseLabels(labels, values.length);

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8.0),
        child: CustomPaint(
          size: Size(width ?? double.infinity, height),
          painter: _DuiChartPainter(
            chartType: chartType,
            values: values,
            labels: parsedLabels,
            primaryColor: primaryColor,
            secondaryColor: secColor,
            gridColor: gridColor,
            labelColor: labelColor,
            minY: minY,
            maxY: maxY,
            showGrid: showGrid,
            showLabels: showLabels,
            showDots: showDots,
            filled: filled,
            strokeWidth: strokeWidth,
            customBarWidth: barWidth,
          ),
        ),
      ),
    );
  }

  static List<double> _parseValues(dynamic raw) {
    if (raw == null) return const [];
    if (raw is List) {
      return raw.map((e) => DuiUtils.tryDouble(e) ?? 0.0).toList();
    }
    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
        try {
          final decoded = jsonDecode(trimmed);
          if (decoded is List) {
            return decoded.map((e) => DuiUtils.tryDouble(e) ?? 0.0).toList();
          }
        } catch (_) {}
      }
      return trimmed
          .split(',')
          .map((s) => DuiUtils.tryDouble(s.trim()))
          .whereType<double>()
          .toList();
    }
    if (raw is Map) {
      final vals = raw['values'] ?? raw['data'];
      if (vals != null) return _parseValues(vals);
    }
    return const [];
  }

  static List<String> _parseLabels(dynamic raw, int count) {
    if (raw is List) {
      return raw.map((e) => e.toString()).toList();
    }
    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
        try {
          final decoded = jsonDecode(trimmed);
          if (decoded is List) {
            return decoded.map((e) => e.toString()).toList();
          }
        } catch (_) {}
      }
      return trimmed.split(',').map((s) => s.trim()).toList();
    }
    return List.generate(count, (i) => '${i + 1}');
  }
}

class _DuiChartPainter extends CustomPainter {
  final String chartType;
  final List<double> values;
  final List<String> labels;
  final Color primaryColor;
  final Color secondaryColor;
  final Color gridColor;
  final Color labelColor;
  final double? minY;
  final double? maxY;
  final bool showGrid;
  final bool showLabels;
  final bool showDots;
  final bool filled;
  final double strokeWidth;
  final double? customBarWidth;

  _DuiChartPainter({
    required this.chartType,
    required this.values,
    required this.labels,
    required this.primaryColor,
    required this.secondaryColor,
    required this.gridColor,
    required this.labelColor,
    required this.minY,
    required this.maxY,
    required this.showGrid,
    required this.showLabels,
    required this.showDots,
    required this.filled,
    required this.strokeWidth,
    required this.customBarWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final leftMargin = showLabels ? 32.0 : 8.0;
    final bottomMargin = showLabels ? 24.0 : 8.0;
    const topMargin = 12.0;
    const rightMargin = 12.0;

    final chartWidth = size.width - leftMargin - rightMargin;
    final chartHeight = size.height - topMargin - bottomMargin;

    if (chartWidth <= 0 || chartHeight <= 0) return;

    // 计算 Y 轴范围
    double effectiveMin = minY ?? 0.0;
    double effectiveMax = maxY ?? 10.0;
    if (values.isNotEmpty) {
      final dataMin = values.reduce(math.min);
      final dataMax = values.reduce(math.max);
      if (minY == null) {
        effectiveMin = dataMin < 0 ? dataMin * 1.1 : 0.0;
      }
      if (maxY == null) {
        effectiveMax = dataMax == 0.0 ? 10.0 : (dataMax > 0 ? dataMax * 1.15 : dataMax * 0.85);
      }
    }
    if (effectiveMax <= effectiveMin) {
      effectiveMax = effectiveMin + 1.0;
    }
    final yRange = effectiveMax - effectiveMin;

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1.0;

    // 绘制网格线与 Y 轴刻度
    const gridDivisions = 4;
    for (int i = 0; i <= gridDivisions; i++) {
      final ratio = i / gridDivisions;
      final y = topMargin + chartHeight * (1.0 - ratio);

      if (showGrid) {
        canvas.drawLine(
          Offset(leftMargin, y),
          Offset(leftMargin + chartWidth, y),
          gridPaint,
        );
      }

      if (showLabels) {
        final val = effectiveMin + yRange * ratio;
        final labelText = val.abs() >= 100 ? val.toStringAsFixed(0) : val.toStringAsFixed(1);
        final tp = TextPainter(
          text: TextSpan(
            text: labelText,
            style: TextStyle(color: labelColor, fontSize: 9.0),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(leftMargin - tp.width - 4, y - tp.height / 2));
      }
    }

    if (values.isEmpty) return;

    // 绘制具体图表数据
    if (chartType == 'bar') {
      _paintBarChart(
        canvas,
        chartWidth,
        chartHeight,
        leftMargin,
        topMargin,
        effectiveMin,
        yRange,
      );
    } else {
      _paintLineChart(
        canvas,
        chartWidth,
        chartHeight,
        leftMargin,
        topMargin,
        effectiveMin,
        yRange,
      );
    }

    // 绘制 X 轴标签
    if (showLabels) {
      final count = values.length;
      for (int i = 0; i < count; i++) {
        if (i >= labels.length) break;
        double x;
        if (count == 1) {
          x = leftMargin + chartWidth / 2;
        } else {
          x = leftMargin + (i / (count - 1)) * chartWidth;
        }
        if (chartType == 'bar') {
          final slotWidth = chartWidth / count;
          x = leftMargin + slotWidth * i + slotWidth / 2;
        }

        final tp = TextPainter(
          text: TextSpan(
            text: labels[i],
            style: TextStyle(color: labelColor, fontSize: 9.0),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(
          canvas,
          Offset(x - tp.width / 2, size.height - bottomMargin + 4),
        );
      }
    }
  }

  void _paintLineChart(
    Canvas canvas,
    double chartWidth,
    double chartHeight,
    double leftMargin,
    double topMargin,
    double minVal,
    double range,
  ) {
    final count = values.length;
    final points = <Offset>[];

    for (int i = 0; i < count; i++) {
      final x = count == 1
          ? leftMargin + chartWidth / 2
          : leftMargin + (i / (count - 1)) * chartWidth;
      final normalized = (values[i] - minVal) / range;
      final y = topMargin + chartHeight * (1.0 - normalized.clamp(0.0, 1.0));
      points.add(Offset(x, y));
    }

    if (points.isEmpty) return;

    final linePath = Path();
    linePath.moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      linePath.lineTo(points[i].dx, points[i].dy);
    }

    // 渐变填充
    if (filled && points.length > 1) {
      final fillPath = Path.from(linePath);
      fillPath.lineTo(points.last.dx, topMargin + chartHeight);
      fillPath.lineTo(points.first.dx, topMargin + chartHeight);
      fillPath.close();

      final fillPaint = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            secondaryColor.withValues(alpha: 0.35),
            secondaryColor.withValues(alpha: 0.02),
          ],
        ).createShader(Rect.fromLTWH(leftMargin, topMargin, chartWidth, chartHeight))
        ..style = PaintingStyle.fill;

      canvas.drawPath(fillPath, fillPaint);
    }

    // 折线
    final strokePaint = Paint()
      ..color = primaryColor
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(linePath, strokePaint);

    // 数据点小圆圈
    if (showDots) {
      final dotPaint = Paint()
        ..color = primaryColor
        ..style = PaintingStyle.fill;
      final innerDotPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;

      for (final pt in points) {
        canvas.drawCircle(pt, strokeWidth * 1.5, dotPaint);
        canvas.drawCircle(pt, strokeWidth * 0.75, innerDotPaint);
      }
    }
  }

  void _paintBarChart(
    Canvas canvas,
    double chartWidth,
    double chartHeight,
    double leftMargin,
    double topMargin,
    double minVal,
    double range,
  ) {
    final count = values.length;
    final slotWidth = chartWidth / count;
    final bw = customBarWidth ?? math.max(4.0, math.min(slotWidth * 0.6, 28.0));

    final barPaint = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.fill;

    for (int i = 0; i < count; i++) {
      final centerX = leftMargin + slotWidth * i + slotWidth / 2;
      final normalized = (values[i] - minVal) / range;
      final barHeight = chartHeight * normalized.clamp(0.0, 1.0);
      final top = topMargin + chartHeight - barHeight;

      final rect = Rect.fromCenter(
        center: Offset(centerX, top + barHeight / 2),
        width: bw,
        height: barHeight,
      );
      final rrect = RRect.fromRectAndCorners(
        rect,
        topLeft: const Radius.circular(4.0),
        topRight: const Radius.circular(4.0),
      );
      canvas.drawRRect(rrect, barPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _DuiChartPainter oldDelegate) {
    return !listEquals(oldDelegate.values, values) ||
        oldDelegate.primaryColor != primaryColor ||
        oldDelegate.chartType != chartType ||
        oldDelegate.minY != minY ||
        oldDelegate.maxY != maxY;
  }
}
