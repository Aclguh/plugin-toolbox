import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';

/// .ptx 不是 Android MIME 表中的注册类型，FileType.custom 会被 SAF 过滤器
/// 置灰不可选，因此放开为任意文件；选中后在此统一校验扩展名（批量导入逐文件过滤）。
bool isPtxPackage(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot == -1) return false;
  final ext = fileName.substring(dot + 1).toLowerCase();
  return ext == 'ptx' || ext == 'zip';
}

/// 批量导入结果: installed 为成功注册所需的插件对象, 其余为界面展示文案
class PtxImportOutcome {
  PtxImportOutcome({
    required this.installed,
    required this.succeeded,
    required this.failed,
  });

  final List<DynamicPlugin> installed;
  final List<String> succeeded;
  final List<String> failed;
}

/// 逐文件执行安装并汇总成败; 单个文件失败不影响其余文件。
/// [installer] 注入以便测试替身 (生产环境为 PluginInstaller.installFromPtx)。
Future<PtxImportOutcome> importPtxFiles({
  required List<PlatformFile> files,
  required Future<DynamicPlugin> Function(File file) installer,
}) async {
  final installed = <DynamicPlugin>[];
  final succeeded = <String>[];
  final failed = <String>[];
  for (final picked in files) {
    final path = picked.path;
    if (path == null) {
      failed.add('${picked.name}: 无法读取文件');
      continue;
    }
    if (!isPtxPackage(picked.name)) {
      failed.add('${picked.name}: 仅支持 .ptx 或 .zip 插件安装包');
      continue;
    }
    try {
      final plugin = await installer(File(path));
      installed.add(plugin);
      succeeded.add('${plugin.name} v${plugin.version}');
    } on FormatException catch (e) {
      failed.add('${picked.name}: ${e.message}');
    } on FileSystemException {
      failed.add('${picked.name}: 安装包文件读取失败，请确认文件完整后重试');
    } catch (_) {
      failed.add('${picked.name}: 安装失败，发生未知错误');
    }
  }
  return PtxImportOutcome(
      installed: installed, succeeded: succeeded, failed: failed);
}
