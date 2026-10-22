import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:logger/logger.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';

/// 原生桥接层公共基础抽象，提供通道调用、沙箱路径解析与配额校验基础设施
abstract class NativeBridgeBase {
  static const String defaultChannelName = 'com.plugintoolbox/host_native';

  final MethodChannel nativeChannel;
  final Directory pluginRootDir;
  final Logger? logger;
  final int storageQuotaMb;

  NativeBridgeBase({
    required this.pluginRootDir,
    this.storageQuotaMb = 50,
    int? initialSandboxUsedBytes,
    MethodChannel? nativeChannel,
    this.logger,
  })  : nativeChannel =
            nativeChannel ?? const MethodChannel(defaultChannelName),
        _cachedSandboxUsedBytes = initialSandboxUsedBytes;

  void logError(String op, Object e, [StackTrace? st]) {
    logger?.w('PluginNativeBridge: $op 调用失败: $e', error: e, stackTrace: st);
  }

  /// 全部原生方法调用的统一入口：异常与 null 结果一律降级为 [fallback]
  Future<T> invoke<T>(String method, T fallback,
      [Map<String, dynamic>? args]) async {
    try {
      final res = await nativeChannel.invokeMethod<T>(method, args);
      return res ?? fallback;
    } catch (e, st) {
      logError(method, e, st);
      return fallback;
    }
  }

  /// Map 返回型原生调用的统一入口：异常降级为 null
  Future<Map<String, dynamic>?> invokeMap(String method,
      [Map<String, dynamic>? args]) async {
    try {
      return await nativeChannel.invokeMapMethod<String, dynamic>(method, args);
    } catch (e, st) {
      logError(method, e, st);
      return null;
    }
  }

  /// 将插件侧传入的相对或绝对路径解析为沙箱内合法的规范绝对路径
  String? resolveSandboxPath(String path, String op) {
    if (path.isEmpty) return null;
    if (SandboxPath.isAbsolutePath(path)) {
      if (SandboxPath.isSafeResolvedPath(pluginRootDir.path, path)) {
        return path;
      }
      logger?.w('PluginNativeBridge: $op 拒绝越界绝对路径: $path');
      return null;
    }
    if (!SandboxPath.isSafeSubpath(pluginRootDir.path, path)) {
      logger?.w('PluginNativeBridge: $op 拒绝越界路径: $path');
      return null;
    }
    return '${pluginRootDir.path}/$path';
  }

  /// 剔除路径分隔符与连续点号，净化文件选择器传入的文件名
  static String sanitizePickedFileName(String name) {
    var cleaned = name.replaceAll(RegExp(r'[/\\]'), '_');
    cleaned = cleaned.replaceAll(RegExp(r'\.{2,}'), '_');
    cleaned = cleaned.trim();
    return cleaned.isEmpty ? 'picked_file' : cleaned;
  }

  /// 重名时自动追加序号后缀，避免静默覆盖已有文件
  static String uniqueSandboxFileName(Directory dir, String fileName) {
    if (!File('${dir.path}/$fileName').existsSync()) return fileName;
    final dot = fileName.lastIndexOf('.');
    final stem = dot > 0 ? fileName.substring(0, dot) : fileName;
    final ext = dot > 0 ? fileName.substring(dot) : '';
    var seq = 1;
    while (true) {
      final candidate = '$stem($seq)$ext';
      if (!File('${dir.path}/$candidate').existsSync()) return candidate;
      seq++;
    }
  }

  int? _cachedSandboxUsedBytes;

  /// 异步精确计算当前沙箱占用字节数（流式异步 I/O，不阻塞主线程）
  Future<int> calculateSandboxUsedBytes() async {
    if (_cachedSandboxUsedBytes != null) return _cachedSandboxUsedBytes!;
    var bytes = 0;
    try {
      if (await pluginRootDir.exists()) {
        await for (final entity
            in pluginRootDir.list(recursive: true, followLinks: false)) {
          if (entity is File) bytes += await entity.length();
        }
      }
    } catch (_) {}
    _cachedSandboxUsedBytes = bytes;
    return bytes;
  }

  /// 获取当前沙箱已占用字节数（优先常驻内存缓存与增量追踪；若未预热则异步流式预热并快速兜底，淘汰主线程同步扫描）
  int sandboxUsedBytes() {
    if (_cachedSandboxUsedBytes != null) return _cachedSandboxUsedBytes!;
    unawaited(calculateSandboxUsedBytes());
    return 0;
  }

  /// 显式设置或同步沙箱缓存字节数
  void setSandboxUsedBytes(int bytes) {
    _cachedSandboxUsedBytes = bytes < 0 ? 0 : bytes;
  }

  /// 增量更新沙箱缓存字节数
  void updateSandboxUsedBytes(int delta) {
    if (_cachedSandboxUsedBytes != null) {
      _cachedSandboxUsedBytes = (_cachedSandboxUsedBytes! + delta);
      if (_cachedSandboxUsedBytes! < 0) _cachedSandboxUsedBytes = 0;
    }
  }

  /// 异步核对沙箱在追加 [additionalBytes] 后是否仍处于存储配额内
  Future<bool> hasSandboxQuotaForAsync(int additionalBytes) async {
    final maxBytes = storageQuotaMb * 1024 * 1024;
    final used = await calculateSandboxUsedBytes();
    return used + additionalBytes <= maxBytes;
  }

  /// 核对沙箱在追加 [additionalBytes] 后是否仍处于存储配额内
  bool hasSandboxQuotaFor(int additionalBytes) {
    final maxBytes = storageQuotaMb * 1024 * 1024;
    return sandboxUsedBytes() + additionalBytes <= maxBytes;
  }

  Future<String?> pickAndCopyIntoSandbox({
    List<String>? allowedExtensions,
    required FileType type,
    required String op,
  }) async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: (allowedExtensions != null && allowedExtensions.isNotEmpty)
            ? FileType.custom
            : type,
        allowedExtensions: allowedExtensions,
      );
      if (res == null || res.files.isEmpty) return null;
      final file = res.files.first;
      final srcPath = file.path;
      if (srcPath == null) return null;

      final fileName = sanitizePickedFileName(file.name);
      final destDir = Directory('${pluginRootDir.path}/data');
      if (!destDir.existsSync()) {
        destDir.createSync(recursive: true);
      }

      final srcFile = File(srcPath);
      final srcBytes = await srcFile.length();
      if (!await hasSandboxQuotaForAsync(srcBytes)) {
        logger?.w(
            'PluginNativeBridge: $op 超出沙箱配额 ($storageQuotaMb MB)，拒绝写入 $fileName ($srcBytes 字节)');
        return null;
      }

      final uniqueName = uniqueSandboxFileName(destDir, fileName);
      await srcFile.copy('${destDir.path}/$uniqueName');
      updateSandboxUsedBytes(srcBytes);
      return 'data/$uniqueName';
    } catch (e, st) {
      logError(op, e, st);
      return null;
    }
  }
}
