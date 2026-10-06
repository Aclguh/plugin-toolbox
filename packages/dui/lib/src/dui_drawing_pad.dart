import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'dui_state.dart';

/// 单条笔画模型
class DuiDrawingStroke {
  final List<Offset> points;
  final Color color;
  final double strokeWidth;

  const DuiDrawingStroke({
    required this.points,
    required this.color,
    required this.strokeWidth,
  });
}

/// 交互式手绘板/签名板组件，支持手势绘制、笔刷属性调节、重置清空与导出 PNG Base64。
class DuiDrawingPad extends StatefulWidget {
  final double? width;
  final double height;
  final Color? backgroundColor;
  final Color strokeColor;
  final double strokeWidth;
  final double borderRadius;
  final String? refKey;
  final String? outputKey;
  final dynamic clearTrigger;
  final dynamic exportTrigger;
  final DuiState? state;
  final ValueChanged<String>? onExport;
  final VoidCallback? onChanged;

  const DuiDrawingPad({
    super.key,
    this.width,
    this.height = 240.0,
    this.backgroundColor,
    this.strokeColor = const Color(0xFF000000),
    this.strokeWidth = 3.0,
    this.borderRadius = 12.0,
    this.refKey,
    this.outputKey,
    this.clearTrigger,
    this.exportTrigger,
    this.state,
    this.onExport,
    this.onChanged,
  });

  @override
  State<DuiDrawingPad> createState() => _DuiDrawingPadState();
}

class _DuiDrawingPadState extends State<DuiDrawingPad> {
  final List<DuiDrawingStroke> _strokes = [];
  List<Offset> _activePoints = [];
  dynamic _lastClearTrigger;
  dynamic _lastExportTrigger;

  @override
  void initState() {
    super.initState();
    _lastClearTrigger = widget.clearTrigger;
    _lastExportTrigger = widget.exportTrigger;
    _syncState(hasDrawing: false, count: 0);
  }

  @override
  void didUpdateWidget(covariant DuiDrawingPad oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.clearTrigger != _lastClearTrigger &&
        widget.clearTrigger != null &&
        widget.clearTrigger != oldWidget.clearTrigger) {
      _lastClearTrigger = widget.clearTrigger;
      _clear();
    }
    if (widget.exportTrigger != _lastExportTrigger &&
        widget.exportTrigger != null &&
        widget.exportTrigger != oldWidget.exportTrigger) {
      _lastExportTrigger = widget.exportTrigger;
      _export();
    }
  }

  void _clear() {
    setState(() {
      _strokes.clear();
      _activePoints.clear();
    });
    _syncState(hasDrawing: false, count: 0, base64: '');
    widget.onChanged?.call();
  }

  Future<void> _export() async {
    final b64 = await exportBase64();
    if (b64 != null) {
      _syncState(hasDrawing: _strokes.isNotEmpty, count: _strokes.length, base64: b64);
      widget.onExport?.call(b64);
    }
  }

  void _syncState({required bool hasDrawing, required int count, String? base64}) {
    final s = widget.state;
    if (s == null) return;
    if (widget.refKey != null) {
      s.set('${widget.refKey}_has_drawing', hasDrawing);
      s.set('${widget.refKey}_count', count);
      if (base64 != null) {
        s.set('${widget.refKey}_base64', base64);
      }
    }
    if (widget.outputKey != null && base64 != null) {
      s.set(widget.outputKey!, base64);
    }
  }

  /// 将画布笔画光栅化并编码为 PNG Base64
  Future<String?> exportBase64() async {
    final w = (widget.width ?? 320.0).clamp(50.0, 2048.0);
    final h = widget.height.clamp(50.0, 2048.0);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, w, h));

    final bg = widget.backgroundColor ?? Colors.white;
    if (bg != Colors.transparent) {
      canvas.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = bg);
    }

    for (final stroke in _strokes) {
      if (stroke.points.isEmpty) continue;
      final paint = Paint()
        ..color = stroke.color
        ..strokeWidth = stroke.strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      if (stroke.points.length == 1) {
        canvas.drawCircle(
          stroke.points.first,
          stroke.strokeWidth / 2,
          Paint()
            ..color = stroke.color
            ..style = PaintingStyle.fill,
        );
      } else {
        final path = Path();
        path.moveTo(stroke.points.first.dx, stroke.points.first.dy);
        for (int i = 1; i < stroke.points.length; i++) {
          path.lineTo(stroke.points[i].dx, stroke.points[i].dy);
        }
        canvas.drawPath(path, paint);
      }
    }

    final picture = recorder.endRecording();
    final img = await picture.toImage(w.toInt(), h.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) return null;
    return base64Encode(byteData.buffer.asUint8List());
  }

  @override
  Widget build(BuildContext context) {
    final bg = widget.backgroundColor ?? Colors.white;

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: Container(
        width: widget.width,
        height: widget.height,
        color: bg,
        child: GestureDetector(
          onPanStart: (details) {
            setState(() {
              _activePoints = [details.localPosition];
            });
          },
          onPanUpdate: (details) {
            setState(() {
              _activePoints.add(details.localPosition);
            });
          },
          onPanEnd: (details) {
            if (_activePoints.isNotEmpty) {
              setState(() {
                _strokes.add(DuiDrawingStroke(
                  points: List.from(_activePoints),
                  color: widget.strokeColor,
                  strokeWidth: widget.strokeWidth,
                ));
                _activePoints.clear();
              });
              _syncState(hasDrawing: true, count: _strokes.length);
              widget.onChanged?.call();
              // 异步刷新 base64 输出
              exportBase64().then((b64) {
                if (b64 != null && mounted) {
                  _syncState(hasDrawing: true, count: _strokes.length, base64: b64);
                }
              });
            }
          },
          child: CustomPaint(
            size: Size(widget.width ?? double.infinity, widget.height),
            painter: _DuiDrawingPainter(
              strokes: _strokes,
              activePoints: _activePoints,
              activeColor: widget.strokeColor,
              activeWidth: widget.strokeWidth,
            ),
          ),
        ),
      ),
    );
  }
}

class _DuiDrawingPainter extends CustomPainter {
  final List<DuiDrawingStroke> strokes;
  final List<Offset> activePoints;
  final Color activeColor;
  final double activeWidth;

  _DuiDrawingPainter({
    required this.strokes,
    required this.activePoints,
    required this.activeColor,
    required this.activeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      if (stroke.points.isEmpty) continue;
      final paint = Paint()
        ..color = stroke.color
        ..strokeWidth = stroke.strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      if (stroke.points.length == 1) {
        canvas.drawCircle(
          stroke.points.first,
          stroke.strokeWidth / 2,
          Paint()
            ..color = stroke.color
            ..style = PaintingStyle.fill,
        );
      } else {
        final path = Path();
        path.moveTo(stroke.points.first.dx, stroke.points.first.dy);
        for (int i = 1; i < stroke.points.length; i++) {
          path.lineTo(stroke.points[i].dx, stroke.points[i].dy);
        }
        canvas.drawPath(path, paint);
      }
    }

    if (activePoints.isNotEmpty) {
      final paint = Paint()
        ..color = activeColor
        ..strokeWidth = activeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      if (activePoints.length == 1) {
        canvas.drawCircle(
          activePoints.first,
          activeWidth / 2,
          Paint()
            ..color = activeColor
            ..style = PaintingStyle.fill,
        );
      } else {
        final path = Path();
        path.moveTo(activePoints.first.dx, activePoints.first.dy);
        for (int i = 1; i < activePoints.length; i++) {
          path.lineTo(activePoints[i].dx, activePoints[i].dy);
        }
        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DuiDrawingPainter oldDelegate) => true;
}
