import 'dart:io';
import 'package:flutter/material.dart';

import 'plugin_dialog_service.dart';

/// 桌面端平台模拟适配器：为桌面端无相机/原生识别器的场景提供降级输入模拟
class DesktopSimulationAdapter {
  static bool get isDesktop => !Platform.isAndroid && !Platform.isIOS;

  static Future<String?> simulateScanBarcode(
    BuildContext context, {
    String? prompt,
  }) async {
    if (!isDesktop) return null;
    return await PluginDialogService.showPrompt(
      context,
      title: prompt ?? '扫码识别 (桌面模拟)',
      hint: '请输入或粘贴条形码/二维码扫描内容',
    );
  }

  static Future<String?> simulateDecodeBarcode(BuildContext context) async {
    if (!isDesktop) return null;
    return await PluginDialogService.showPrompt(
      context,
      title: '图片二维码识别 (桌面模拟)',
      hint: '未检测到原生条码识别器，可手动输入模拟识别结果',
    );
  }
}
