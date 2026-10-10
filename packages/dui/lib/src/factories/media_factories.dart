import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';

import '../dui_canvas.dart';
import '../dui_chart.dart';
import '../dui_drawing_pad.dart';
import '../dui_html.dart';
import '../dui_markdown.dart';
import '../dui_pixel_grid.dart';
import '../dui_renderer.dart';
import '../dui_state.dart';
import '../dui_utils.dart';

/// 注册媒体与富文本渲染组件工厂 (Image, PixelGrid, Canvas, DrawingPad, Markdown, Chart, Html, etc.)
void registerMediaFactories(DuiRenderer renderer) {
  final state = renderer.state;
  final eventHandler = renderer.eventHandler;

  // ---- 图片显示 (从插件本地沙箱目录加载) ----
  Widget buildImage(DuiNodeContext node) {
    final rawSrc = node.props['src']?.toString() ?? '';
    final rootDir = node.renderer.pluginRootDir;
    final keys = DuiState.extractKeys(rawSrc);

    Widget renderImage() {
      final src = state.interpolate(rawSrc);
      // 路径穿越防御：src 必须归一化后仍严格位于插件沙箱根目录之内，
      // 否则 (例如 "../../etc/passwd") 直接拒绝渲染
      if (rootDir == null ||
          src.isEmpty ||
          !SandboxPath.isSafeSubpath(rootDir.path, src)) {
        return const SizedBox.shrink();
      }
      return Image.file(
        File('${rootDir.path}/$src'),
        width: node.width,
        height: node.height,
        fit: BoxFit.contain,
        cacheWidth: 256,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      );
    }

    if (keys.isNotEmpty) {
      return ListenableBuilder(
        listenable: state.listenableForKeys(keys),
        builder: (_, __) => renderImage(),
      );
    }
    return renderImage();
  }
  renderer.registerFactory('Image', buildImage);

  // ---- 像素网格 (状态 0/1 位图逐格填充, 如二维码矩阵) ----
  renderer.registerFactory('PixelGrid', (node) {
    // data/cols/cellSize 均为渲染期取值, 支持从状态插值
    final data = state.interpolate(node.props['data']?.toString() ?? '');
    final cols =
        DuiUtils.tryInt(state.interpolate(node.props['cols']?.toString() ?? ''));
    final cellSize = DuiUtils.tryDouble(
        state.interpolate(node.props['cellSize']?.toString() ?? ''));
    return DuiPixelGrid(
      data: data,
      cols: cols ?? 0,
      cellSize: cellSize ?? 4.0,
      darkColor:
          DuiUtils.parseColor(node.props['darkColor']) ?? const Color(0xFF000000),
      lightColor: DuiUtils.parseColor(node.props['lightColor']) ??
          const Color(0xFFFFFFFF),
    );
  });

  // ---- 动态指令画板 (Canvas) ----
  renderer.registerFactory('Canvas', (node) {
    final width = node.width ?? 300.0;
    final height = node.height ?? 200.0;
    final bgColor = DuiUtils.parseColor(
      state.interpolate(node.props['backgroundColor']?.toString() ?? ''),
    );
    final rawCommands = node.props['commands'];
    if (rawCommands is String) {
      final keys = DuiState.extractKeys(rawCommands);
      Widget buildCanvas() {
        final interpolated = state.interpolate(rawCommands);
        return DuiCanvas(
          width: width,
          height: height,
          backgroundColor: bgColor,
          commands: interpolated,
        );
      }

      if (keys.isEmpty) return buildCanvas();
      return ListenableBuilder(
        listenable: state.listenableForKeys(keys),
        builder: (_, __) => buildCanvas(),
      );
    }
    return DuiCanvas(
      width: width,
      height: height,
      backgroundColor: bgColor,
      commands: rawCommands,
    );
  });

  // ---- 手绘板 / 签名板 (DrawingPad / SignaturePad) ----
  Widget buildDrawingPad(DuiNodeContext node) {
    final width = node.width;
    final height = node.height ?? 240.0;
    final bg = DuiUtils.parseColor(
      state.interpolate(node.props['backgroundColor']?.toString() ?? ''),
    );
    final strokeColor = DuiUtils.parseColor(
          state.interpolate(node.props['strokeColor']?.toString() ?? ''),
        ) ??
        const Color(0xFF000000);
    final strokeWidth = DuiUtils.tryDouble(
          state.interpolate(node.props['strokeWidth']?.toString() ?? ''),
        ) ??
        3.0;
    final borderRadius =
        DuiUtils.tryDouble(node.props['borderRadius']) ?? 12.0;

    final clearTrigger = node.props['clearTrigger'] != null
        ? state.interpolate(node.props['clearTrigger'].toString())
        : null;
    final exportTrigger = node.props['exportTrigger'] != null
        ? state.interpolate(node.props['exportTrigger'].toString())
        : null;

    final outputKey = node.props['outputKey']?.toString();

    void onExport(String base64) {
      if (node.events.containsKey('onExport')) {
        eventHandler.handleEvent(node.events['onExport'], base64);
      }
    }

    void onChanged() {
      if (node.events.containsKey('onChanged')) {
        eventHandler.handleEvent(node.events['onChanged']);
      }
    }

    return DuiDrawingPad(
      width: width,
      height: height,
      backgroundColor: bg,
      strokeColor: strokeColor,
      strokeWidth: strokeWidth,
      borderRadius: borderRadius,
      refKey: node.ref,
      outputKey: outputKey,
      clearTrigger: clearTrigger,
      exportTrigger: exportTrigger,
      state: state,
      onExport: onExport,
      onChanged: onChanged,
    );
  }

  renderer.registerFactory('DrawingPad', buildDrawingPad);
  renderer.registerFactory('SignaturePad', buildDrawingPad);

  // ---- Markdown 渲染组件 (MarkdownView / Markdown) ----
  Widget buildMarkdown(DuiNodeContext node) {
    final rawText = node.props['text']?.toString() ??
        node.props['data']?.toString() ??
        '';
    final selectable =
        DuiUtils.tryBool(node.props['selectable'], fallback: true);
    final keys = DuiState.extractKeys(rawText);

    Widget renderMd() => DuiMarkdownView(
          data: state.interpolate(rawText),
          selectable: selectable,
        );

    if (keys.isEmpty) return renderMd();
    return ListenableBuilder(
      listenable: state.listenableForKeys(keys),
      builder: (_, __) => renderMd(),
    );
  }
  renderer.registerFactory('MarkdownView', buildMarkdown);
  renderer.registerFactory('Markdown', buildMarkdown);

  // ---- 图表组件 (Chart / LineChart / BarChart) ----
  Widget buildChart(DuiNodeContext node) {
    final chartType = node.props['type']?.toString() ??
        (node.props['chartType']?.toString() ?? 'line');
    final rawData = node.props['data'];
    final rawLabels = node.props['labels'];
    final height = node.height ?? 200.0;
    final width = node.width;
    final color = DuiUtils.parseColor(
      state.interpolate(node.props['color']?.toString() ?? ''),
    );
    final secondaryColor = DuiUtils.parseColor(
      state.interpolate(node.props['secondaryColor']?.toString() ?? ''),
    );
    final backgroundColor = DuiUtils.parseColor(
      state.interpolate(node.props['backgroundColor']?.toString() ?? ''),
    );
    final minY = DuiUtils.tryDouble(node.props['minY']);
    final maxY = DuiUtils.tryDouble(node.props['maxY']);
    final showGrid = DuiUtils.tryBool(node.props['showGrid'], fallback: true);
    final showLabels = DuiUtils.tryBool(node.props['showLabels'], fallback: true);
    final showDots = DuiUtils.tryBool(node.props['showDots'], fallback: true);
    final filled = DuiUtils.tryBool(node.props['filled'], fallback: true);
    final strokeWidth = DuiUtils.tryDouble(node.props['strokeWidth']) ?? 2.5;
    final barWidth = DuiUtils.tryDouble(node.props['barWidth']);

    final dataStr = rawData is String
        ? rawData
        : (rawData != null ? jsonEncode(rawData) : '');
    final keys = <String>{
      ...DuiState.extractKeys(dataStr),
      if (rawLabels is String) ...DuiState.extractKeys(rawLabels),
    };

    Widget renderChart() {
      dynamic effectiveData = rawData;
      if (rawData is String) {
        effectiveData = state.interpolate(rawData);
      }
      dynamic effectiveLabels = rawLabels;
      if (rawLabels is String) {
        effectiveLabels = state.interpolate(rawLabels);
      }

      return DuiChart(
        chartType: chartType,
        data: effectiveData,
        labels: effectiveLabels,
        width: width,
        height: height,
        color: color,
        secondaryColor: secondaryColor,
        backgroundColor: backgroundColor,
        minY: minY,
        maxY: maxY,
        showGrid: showGrid,
        showLabels: showLabels,
        showDots: showDots,
        filled: filled,
        strokeWidth: strokeWidth,
        barWidth: barWidth,
      );
    }

    if (keys.isEmpty) return renderChart();
    return ListenableBuilder(
      listenable: state.listenableForKeys(keys),
      builder: (_, __) => renderChart(),
    );
  }
  renderer.registerFactory('Chart', buildChart);
  renderer.registerFactory('LineChart', (n) {
    n.props['type'] = 'line';
    return buildChart(n);
  });
  renderer.registerFactory('BarChart', (n) {
    n.props['type'] = 'bar';
    return buildChart(n);
  });

  // ---- 富文本组件 (Html / HtmlView) ----
  Widget buildHtml(DuiNodeContext node) {
    final rawText = node.props['html']?.toString() ??
        node.props['text']?.toString() ??
        node.props['data']?.toString() ??
        '';
    final selectable =
        DuiUtils.tryBool(node.props['selectable'], fallback: true);
    final keys = DuiState.extractKeys(rawText);

    void onLinkTap(String url) {
      if (node.events.containsKey('onLinkTap')) {
        eventHandler.handleEvent(node.events['onLinkTap'], url);
      }
    }

    Widget renderHtml() => DuiHtml(
          html: state.interpolate(rawText),
          selectable: selectable,
          onLinkTap: onLinkTap,
        );

    if (keys.isEmpty) return renderHtml();
    return ListenableBuilder(
      listenable: state.listenableForKeys(keys),
      builder: (_, __) => renderHtml(),
    );
  }
  renderer.registerFactory('Html', buildHtml);
  renderer.registerFactory('HtmlView', buildHtml);
}
