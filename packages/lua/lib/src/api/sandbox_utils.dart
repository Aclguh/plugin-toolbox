/// 沙箱路径解析与受保护清单判定的共享工具。
///
/// 此前 fs/image/archive/share/camera/vision/audio 七个 API 各自复制同一份
/// `resolveSafePath` 闭包，收敛于此统一维护，避免校验逻辑漂移。
library;

import 'dart:io';

import 'package:lua_dardo/lua.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';

/// 将插件沙箱相对路径 [relPath] 解析为受限绝对路径。
///
/// 沙箱未挂载或路径越界时直接抛出 Lua 错误（不返回），调用方无需判空。
String resolveSandboxPath(LuaState ls, PluginContext context, String relPath) {
  final rootDir = context.rootDir;
  if (rootDir == null) {
    ls.error2('沙箱未挂载: 当前插件上下文缺少 rootDir');
    return '';
  }
  if (!SandboxPath.isSafeSubpath(rootDir.path, relPath)) {
    ls.error2('非法路径: 禁止逃逸沙箱 ($relPath)');
    return '';
  }
  final fullPath = '${rootDir.path}/$relPath';
  bool isSymlinkEscape = false;
  try {
    if (rootDir.existsSync()) {
      final rootRealPath = rootDir.resolveSymbolicLinksSync();
      FileSystemEntity current = File(fullPath);
      while (current.path.length >= rootDir.path.length) {
        final type =
            FileSystemEntity.typeSync(current.path, followLinks: false);
        if (type != FileSystemEntityType.notFound) {
          final real = current.resolveSymbolicLinksSync();
          if (!SandboxPath.isSafeResolvedPath(rootRealPath, real)) {
            isSymlinkEscape = true;
          }
          break;
        }
        final parent = current.parent;
        if (parent.path == current.path) break;
        current = parent;
      }
    }
  } on FileSystemException {
    ls.error2('符号链接解析失败: 拒绝访问未知路径 ($relPath)');
    return '';
  }

  if (isSymlinkEscape) {
    ls.error2('非法符号链接: 目标逃逸沙箱根目录 ($relPath)');
    return '';
  }
  return fullPath;
}

/// 按 [SandboxPath] 相同的分段归一化规则解析相对路径（剔除 `.` 与空段）。
///
/// 调用前应先经 [SandboxPath.isSafeSubpath] 校验，故此处不可能出现 `..` 段。
String normalizeSandboxRelPath(String relPath) {
  final resolved = <String>[];
  for (final seg in relPath.replaceAll('\\', '/').split('/')) {
    if (seg.isEmpty || seg == '.') continue;
    resolved.add(seg);
  }
  return resolved.join('/');
}

/// 判定 [relPath] 归一化后是否命中沙箱根部的受保护核心清单
/// （`plugin.json` / `manifest.json`）。
///
/// 必须做归一化绝对路径比较而非字符串等值：`./plugin.json` 可经路径归一化
/// 绕过等值判断覆写自身清单，下次启动按新清单授权形成静默提权。
bool isProtectedSandboxFile(PluginContext context, String relPath) {
  final rootDir = context.rootDir;
  if (rootDir == null) return false;
  final rootPath =
      rootDir.path.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '');
  final normalizedRel = normalizeSandboxRelPath(relPath);
  if (normalizedRel.isEmpty) return false;
  final absPath = '$rootPath/$normalizedRel';
  return absPath == '$rootPath/plugin.json' ||
      absPath == '$rootPath/manifest.json';
}
