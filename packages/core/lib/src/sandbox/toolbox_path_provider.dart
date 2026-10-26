import 'dart:io';

/// 跨平台纯 Dart 路径提供者抽象接口，使核心包解耦于具体的平台通道实现
abstract interface class ToolboxPathProvider {
  /// 插件解压安装与沙箱根目录
  Directory get pluginsDirectory;

  /// 插件下载缓存与解压暂存目录
  Directory get tempDirectory;
}

/// 基于本地文件系统 Directory 的纯 Dart 路径提供者实现
class DirectoryPathProvider implements ToolboxPathProvider {
  final Directory _pluginsDirectory;
  final Directory _tempDirectory;

  DirectoryPathProvider({
    required Directory pluginsDirectory,
    Directory? tempDirectory,
  })  : _pluginsDirectory = pluginsDirectory,
        _tempDirectory = tempDirectory ?? Directory.systemTemp;

  @override
  Directory get pluginsDirectory => _pluginsDirectory;

  @override
  Directory get tempDirectory => _tempDirectory;
}
