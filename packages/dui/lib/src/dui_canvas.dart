import 'dart:convert';
import 'package:flutter/material.dart';
import 'dui_utils.dart';

/// 动态指令画板组件，基于声明式指令集在 Flutter Canvas 上进行绘制。
class DuiCanvas extends StatelessWidget {
  final double width;
  final double height;
  final dynamic commands;
  final Color? backgroundColor;

  const DuiCanvas({
    super.key,
    required this.width,
    required this.height,
    required this.commands,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final parsedCommands = _parseCommands(commands);
    return Container(
      width: width,
      height: height,
      color: backgroundColor,
      child: CustomPaint(
        size: Size(width, height),
        painter: DuiCanvasPainter(parsedCommands),
      ),
    );
  }

  static List<Map<String, dynamic>> _parseCommands(dynamic raw) {
    if (raw == null) return const [];
    if (raw is List) {
      return raw.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
    }
    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
        try {
          final decoded = json.decode(trimmed);
          if (decoded is List) {
            return decoded
                .whereType<Map>()
                .map((m) => Map<String, dynamic>.from(m))
                .toList();
          }
        } catch (_) {}
      }
    }
    return const [];
  }
}

class DuiCanvasPainter extends CustomPainter {
  final List<Map<String, dynamic>> commands;

  const DuiCanvasPainter(this.commands);

  @override
  void paint(Canvas canvas, Size size) {
    for (final cmd in commands) {
      final type = cmd['type']?.toString().toLowerCase();
      switch (type) {
        case 'line':
          _drawLine(canvas, cmd);
          break;
        case 'rect':
          _drawRect(canvas, cmd);
          break;
        case 'circle':
          _drawCircle(canvas, cmd);
          break;
        case 'arc':
          _drawArc(canvas, cmd);
          break;
        case 'text':
          _drawText(canvas, cmd);
          break;
        case 'clear':
          final color = DuiUtils.parseColor(cmd['color']?.toString()) ?? Colors.transparent;
          canvas.drawColor(color, BlendMode.src);
          break;
      }
    }
  }

  void _drawLine(Canvas canvas, Map<String, dynamic> cmd) {
    final x1 = DuiUtils.tryDouble(cmd['x1']) ?? 0.0;
    final y1 = DuiUtils.tryDouble(cmd['y1']) ?? 0.0;
    final x2 = DuiUtils.tryDouble(cmd['x2']) ?? 0.0;
    final y2 = DuiUtils.tryDouble(cmd['y2']) ?? 0.0;
    final color = DuiUtils.parseColor(cmd['color']?.toString()) ?? const Color(0xFFB4C9FF);
    final strokeWidth = DuiUtils.tryDouble(cmd['strokeWidth']) ?? 1.0;

    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(x1, y1), Offset(x2, y2), paint);
  }

  void _drawRect(Canvas canvas, Map<String, dynamic> cmd) {
    final x = DuiUtils.tryDouble(cmd['x']) ?? 0.0;
    final y = DuiUtils.tryDouble(cmd['y']) ?? 0.0;
    final w = DuiUtils.tryDouble(cmd['width']) ?? 0.0;
    final h = DuiUtils.tryDouble(cmd['height']) ?? 0.0;
    final color = DuiUtils.parseColor(cmd['color']?.toString()) ?? const Color(0xFFB4C9FF);
    final styleStr = cmd['style']?.toString().toLowerCase();
    final strokeWidth = DuiUtils.tryDouble(cmd['strokeWidth']) ?? 1.0;
    final radius = DuiUtils.tryDouble(cmd['borderRadius']);

    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = styleStr == 'stroke' ? PaintingStyle.stroke : PaintingStyle.fill;

    final rect = Rect.fromLTWH(x, y, w, h);
    if (radius != null && radius > 0) {
      canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)), paint);
    } else {
      canvas.drawRect(rect, paint);
    }
  }

  void _drawCircle(Canvas canvas, Map<String, dynamic> cmd) {
    final cx = DuiUtils.tryDouble(cmd['cx']) ?? 0.0;
    final cy = DuiUtils.tryDouble(cmd['cy']) ?? 0.0;
    final radius = DuiUtils.tryDouble(cmd['radius']) ?? 0.0;
    final color = DuiUtils.parseColor(cmd['color']?.toString()) ?? const Color(0xFFB4C9FF);
    final styleStr = cmd['style']?.toString().toLowerCase();
    final strokeWidth = DuiUtils.tryDouble(cmd['strokeWidth']) ?? 1.0;

    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = styleStr == 'stroke' ? PaintingStyle.stroke : PaintingStyle.fill;

    canvas.drawCircle(Offset(cx, cy), radius, paint);
  }

  void _drawArc(Canvas canvas, Map<String, dynamic> cmd) {
    final x = DuiUtils.tryDouble(cmd['x']) ?? 0.0;
    final y = DuiUtils.tryDouble(cmd['y']) ?? 0.0;
    final w = DuiUtils.tryDouble(cmd['width']) ?? 0.0;
    final h = DuiUtils.tryDouble(cmd['height']) ?? 0.0;
    final startAngle = DuiUtils.tryDouble(cmd['startAngle']) ?? 0.0;
    final sweepAngle = DuiUtils.tryDouble(cmd['sweepAngle']) ?? 0.0;
    final useCenter = DuiUtils.tryBool(cmd['useCenter']);
    final color = DuiUtils.parseColor(cmd['color']?.toString()) ?? const Color(0xFFB4C9FF);
    final styleStr = cmd['style']?.toString().toLowerCase();
    final strokeWidth = DuiUtils.tryDouble(cmd['strokeWidth']) ?? 1.0;

    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = styleStr == 'stroke' ? PaintingStyle.stroke : PaintingStyle.fill;

    canvas.drawArc(Rect.fromLTWH(x, y, w, h), startAngle, sweepAngle, useCenter, paint);
  }

  void _drawText(Canvas canvas, Map<String, dynamic> cmd) {
    final text = cmd['text']?.toString() ?? '';
    final x = DuiUtils.tryDouble(cmd['x']) ?? 0.0;
    final y = DuiUtils.tryDouble(cmd['y']) ?? 0.0;
    final fontSize = DuiUtils.tryDouble(cmd['fontSize']) ?? 14.0;
    final color = DuiUtils.parseColor(cmd['color']?.toString()) ?? const Color(0xFFB4C9FF);

    final textSpan = TextSpan(
      text: text,
      style: TextStyle(color: color, fontSize: fontSize),
    );
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(x, y));
  }

  @override
  bool shouldRepaint(covariant DuiCanvasPainter oldDelegate) => true;
}
