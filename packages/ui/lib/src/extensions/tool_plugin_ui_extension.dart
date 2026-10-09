import 'dart:io';
import 'package:flutter/material.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';

/// 表现层为 [ToolPlugin] 提供的 UI 扩展能力，保持 Core 纯领域层单向依赖
extension ToolPluginUiExtension on ToolPlugin {
  /// 获取插件对应的 Material 矢量图标
  IconData get icon {
    switch (iconName.toLowerCase()) {
      case 'code':
        return Icons.code_rounded;
      case 'security':
      case 'hash':
        return Icons.security_rounded;
      case 'calculate':
      case 'calculator':
        return Icons.calculate_rounded;
      case 'qr':
      case 'qrcode':
        return Icons.qr_code_rounded;
      case 'build':
      default:
        return const IconData(0xe247, fontFamily: 'MaterialIcons');
    }
  }

  /// 获取本地图片图标提供器（当存在本地文件时）
  ImageProvider? get iconProvider {
    final path = iconPath;
    if (path != null && path.isNotEmpty) {
      final file = File(path);
      if (file.existsSync()) {
        return FileImage(file);
      }
    }
    return null;
  }
}
