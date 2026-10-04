import 'package:flutter/material.dart';

/// 像素网格组件: 将状态中的行主序 0/1 位图字符串渲染为实心像素方块。
///
/// 为二维码等确定性图形提供像素级渲染通道, 取代插件侧的字符拼接模拟
/// (依赖等宽字体度量、需 NBSP 防换行、缩放与对齐均不可控)。
class DuiPixelGrid extends StatelessWidget {
  /// 行主序 0/1 位图, 长度必须能被 [cols] 整除
  final String data;

  /// 每行格子数 (列数); 行数由 data 长度与 cols 推导
  final int cols;

  /// 单格逻辑像素边长; 插件侧应传整数值以保证像素边缘清晰
  final double cellSize;

  final Color darkColor;
  final Color lightColor;

  const DuiPixelGrid({
    super.key,
    required this.data,
    required this.cols,
    required this.cellSize,
    this.darkColor = const Color(0xFF000000),
    this.lightColor = const Color(0xFFFFFFFF),
  });

  @override
  Widget build(BuildContext context) {
    // 数据不完整 (空串/长度与列数不匹配) 时安全降级为空白, 不抛异常
    if (cols <= 0 || data.isEmpty || data.length % cols != 0) {
      return const SizedBox.shrink();
    }
    final rows = data.length ~/ cols;
    return SizedBox(
      width: cols * cellSize,
      height: rows * cellSize,
      child: CustomPaint(
        painter: _PixelGridPainter(
          cells: data,
          cols: cols,
          rows: rows,
          cellSize: cellSize,
          darkColor: darkColor,
          lightColor: lightColor,
        ),
      ),
    );
  }
}

class _PixelGridPainter extends CustomPainter {
  final String cells;
  final int cols;
  final int rows;
  final double cellSize;
  final Color darkColor;
  final Color lightColor;

  const _PixelGridPainter({
    required this.cells,
    required this.cols,
    required this.rows,
    required this.cellSize,
    required this.darkColor,
    required this.lightColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = lightColor);
    final darkPaint = Paint()..color = darkColor;
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        if (cells.codeUnitAt(r * cols + c) == 0x31) {
          canvas.drawRect(
            Rect.fromLTWH(c * cellSize, r * cellSize, cellSize, cellSize),
            darkPaint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PixelGridPainter oldDelegate) {
    return oldDelegate.cells != cells ||
        oldDelegate.cols != cols ||
        oldDelegate.cellSize != cellSize ||
        oldDelegate.darkColor != darkColor ||
        oldDelegate.lightColor != lightColor;
  }
}
