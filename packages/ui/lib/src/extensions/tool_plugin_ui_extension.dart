import 'dart:io';
import 'package:flutter/material.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';

/// 图标 ImageProvider 缓存（按文件绝对路径为键）。
///
/// 卡片在列表滚动中会高频重建，若每次 build 都 existsSync 触盘会造成
/// 主线程同步 IO 抖动；图标文件在安装/卸载期才变化，运行期可安全缓存。
/// LinkedHashMap 保持插入序，命中时重插实现 LRU 语义，超限淘汰最久未用项。
final Map<String, ImageProvider?> _iconProviderCache =
    <String, ImageProvider?>{};

const int _iconProviderCacheLimit = 64;

/// 使插件图标缓存失效。
///
/// [iconPath] 为空时清空全部缓存；插件安装/升级/卸载后应调用本钩子，
/// 否则旧图标会被缓存命中而继续展示。
void invalidatePluginIconCache([String? iconPath]) {
  if (iconPath == null) {
    _iconProviderCache.clear();
  } else {
    _iconProviderCache.remove(iconPath);
  }
}

ImageProvider? _resolveIconProvider(String path) {
  if (_iconProviderCache.containsKey(path)) {
    // 命中后重插到尾部，维持 LRU 热度序
    final provider = _iconProviderCache.remove(path);
    _iconProviderCache[path] = provider;
    return provider;
  }
  // 仅缓存未命中时才触盘，结果（含文件缺失的 null）一并缓存
  final file = File(path);
  final provider = file.existsSync() ? FileImage(file) : null;
  _iconProviderCache[path] = provider;
  if (_iconProviderCache.length > _iconProviderCacheLimit) {
    _iconProviderCache.remove(_iconProviderCache.keys.first);
  }
  return provider;
}

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

  /// 获取本地图片图标提供器（当存在本地文件时，经 LRU 缓存避免 build 期同步 IO）
  ImageProvider? get iconProvider {
    final path = iconPath;
    if (path == null || path.isEmpty) return null;
    return _resolveIconProvider(path);
  }
}
