import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../model/plugin_manifest.dart';
import '../security/plugin_signature.dart';
import 'jsdelivr_plugin_store_source.dart' show PluginStoreException;

/// 安装包内清单与顶层文件的一致性核对结果。
class PluginPackageContract {
  const PluginPackageContract({
    required this.manifest,
    required this.entryNames,
    required this.missingEntryScript,
    required this.missingUiDefinition,
    this.signatureResult,
  });

  /// 安装包内的插件清单
  final PluginManifest manifest;

  /// 安装包内的全部文件条目名
  final Set<String> entryNames;

  /// 清单声明的入口脚本在包内缺失
  final bool missingEntryScript;

  /// 清单声明的 UI 描述文件在包内缺失
  final bool missingUiDefinition;

  /// 可选的数字签名校验结果
  final PluginSignatureVerificationResult? signatureResult;

  bool get isConsistent => !missingEntryScript && !missingUiDefinition;
  bool get hasValidSignature => signatureResult?.isValid ?? false;
}

/// 在不落盘的前提下读取 .ptx 内的清单与文件清单。
///
/// 商店的元数据来自 `plugin-source`，安装包来自 `dist`，两者由仓库中不同提交
/// 产出时可能出现 id / 入口脚本不一致；安装前用本函数把两者对齐，
/// 把"装上一个必然报错的插件"变成一条可见提示。
PluginPackageContract inspectPluginPackage(
  Uint8List bytes, {
  PluginSignatureVerifier? signatureVerifier,
}) {
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    throw const PluginStoreException('安装包不是有效的 ZIP/PTX 格式');
  }

  final names = <String>{};
  for (final file in archive) {
    if (file.isFile) names.add(file.name);
  }

  final manifestEntry = archive.findFile('plugin.json');
  if (manifestEntry == null) {
    throw const PluginStoreException('安装包中未找到 plugin.json 清单文件');
  }

  final PluginManifest manifest;
  try {
    manifest = PluginManifest.fromJsonString(
      utf8.decode(manifestEntry.content as List<int>),
    );
  } on FormatException catch (e) {
    throw PluginStoreException('安装包内的 plugin.json 无法解析: ${e.message}');
  }

  final sigResult = signatureVerifier?.verifyArchive(archive);
  if (signatureVerifier != null && signatureVerifier.requireSignature) {
    if (sigResult == null || !sigResult.isValid) {
      throw PluginStoreException('插件签名校验未通过: ${sigResult?.message}');
    }
  }

  return PluginPackageContract(
    manifest: manifest,
    entryNames: names,
    missingEntryScript: !names.contains(manifest.entry),
    missingUiDefinition: !names.contains(manifest.ui),
    signatureResult: sigResult,
  );
}

/// 计算指定安装包字节序列的 SHA-256 哈希值 (小写十六进制字符串)
String calculatePackageSha256(List<int> bytes) =>
    sha256.convert(bytes).toString().toLowerCase();

/// 核对指定安装包字节序列是否与期望的 [expectedHash] (十六进制或 base64) 匹配
bool verifyPackageSha256(List<int> bytes, String expectedHash) {
  final clean = expectedHash.trim();
  if (clean.isEmpty) return false;
  final digest = sha256.convert(bytes);
  return clean.toLowerCase() == digest.toString().toLowerCase() ||
      clean == base64.encode(digest.bytes);
}
