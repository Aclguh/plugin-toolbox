/// 沙箱路径安全校验工具。
///
/// 纯 Dart 实现且不依赖任何第三方包，保证 `tool/verify.dart` 能以纯 Dart
/// 脚本方式直接导入并断言生产算法（与宿主运行时使用同一份代码）。
class SandboxPath {
  SandboxPath._();

  /// 检查 [relativeSubpath] 拼接到 [basePath] 之后是否仍严格位于沙箱内部。
  ///
  /// 防御能力：
  /// - 任意连续点号（`..`、`....` 等）视为路径穿越混淆，直接拒绝；
  /// - Windows 风格反斜杠统一按分隔符处理后再解析；
  /// - 绝对路径（POSIX 根 `/`、Windows 盘符 `C:\`、UNC `\\server\share`）
  ///   不属于"相对子路径"，一律拒绝。
  static bool isSafeSubpath(String basePath, String relativeSubpath) {
    if (relativeSubpath.isEmpty) return false;
    if (relativeSubpath.contains(RegExp(r'\.{2,}'))) return false;
    if (isAbsolutePath(relativeSubpath)) return false;

    final cleanBase = basePath.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '');
    final fullPath = '$cleanBase/${relativeSubpath.replaceAll('\\', '/')}';
    final resolved = <String>[];
    for (final seg in fullPath.split('/')) {
      if (seg == '' || seg == '.') continue;
      if (seg == '..') {
        if (resolved.isEmpty) return false;
        resolved.removeLast();
      } else {
        resolved.add(seg);
      }
    }
    final baseSegments = cleanBase.split('/').where((s) => s.isNotEmpty).toList();
    if (resolved.length < baseSegments.length) return false;
    for (int i = 0; i < baseSegments.length; i++) {
      if (resolved[i] != baseSegments[i]) return false;
    }
    return true;
  }

  /// 校验压缩包（.ptx/ZIP）内的条目相对路径是否可以安全解压到沙箱目录。
  ///
  /// 相比 [isSafeSubpath] 更严格：任何 `..` 段、绝对路径、空路径或包含
  /// NUL 字节的条目都会被拒绝，从源头封堵 Zip Slip 攻击。
  static bool isSafeRelativeEntry(String entry) {
    if (entry.isEmpty) return false;
    if (entry.contains('\u0000')) return false;
    if (entry.contains(RegExp(r'\.{2,}'))) return false;
    if (isAbsolutePath(entry)) return false;

    final resolved = <String>[];
    for (final seg in entry.replaceAll('\\', '/').split('/')) {
      if (seg == '' || seg == '.') continue;
      if (seg == '..') return false;
      resolved.add(seg);
    }
    return resolved.isNotEmpty;
  }

  /// 判断 [path] 是否为绝对路径：POSIX 根、Windows 盘符（含盘符相对形式
  /// `C:file`）与 UNC 路径均视为绝对，避免在 Windows 主机上逃出沙箱根。
  static bool isAbsolutePath(String path) {
    if (path.isEmpty) return false;
    if (path.startsWith('/') || path.startsWith('\\')) return true;
    if (path.length >= 2 && path.codeUnitAt(1) == 0x3A /* : */) {
      final drive = path.codeUnitAt(0);
      final isLetter =
          (drive >= 0x41 && drive <= 0x5A) || (drive >= 0x61 && drive <= 0x7A);
      if (isLetter) return true;
    }
    return false;
  }
}
