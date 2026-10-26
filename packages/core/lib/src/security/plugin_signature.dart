import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'ed25519.dart';

/// 插件数字签名实体
class PluginSignature {
  /// 签名算法（默认 'Ed25519'）
  final String algorithm;

  /// 开发者公钥（十六进制编码）
  final String publicKey;

  /// 数字签名（十六进制编码，64 字节 Ed25519 签名）
  final String signature;

  /// 可选的密钥标识或开发者 ID
  final String? keyId;

  /// 签名生成时间戳
  final DateTime? timestamp;

  const PluginSignature({
    this.algorithm = 'Ed25519',
    required this.publicKey,
    required this.signature,
    this.keyId,
    this.timestamp,
  });

  Map<String, dynamic> toJson() => {
        'algorithm': algorithm,
        'publicKey': publicKey,
        'signature': signature,
        if (keyId != null) 'keyId': keyId,
        if (timestamp != null) 'timestamp': timestamp!.toIso8601String(),
      };

  factory PluginSignature.fromJson(Map<String, dynamic> json) {
    return PluginSignature(
      algorithm: json['algorithm'] as String? ?? 'Ed25519',
      publicKey: json['publicKey'] as String? ?? '',
      signature: json['signature'] as String? ?? '',
      keyId: json['keyId'] as String?,
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'] as String)
          : null,
    );
  }

  @override
  String toString() => jsonEncode(toJson());
}

/// 签名校验结果状态枚举
enum VerificationStatus {
  /// 签名合法且公钥受信任
  valid,

  /// 未包含数字签名
  missingSignature,

  /// 数字签名无效或内容已被篡改
  tampered,

  /// 签名格式损坏或解析失败
  malformed,

  /// 签名算法不受支持
  unsupportedAlgorithm,

  /// 签名合法但公钥不在受信任白名单内
  untrustedKey,

  /// 未配置强制验签且包未签名（开发兼容态）
  unsigned,
}

/// 插件数字签名校验结果
class PluginSignatureVerificationResult {
  final VerificationStatus status;
  final String? publicKey;
  final String? keyId;
  final String? message;

  const PluginSignatureVerificationResult({
    required this.status,
    this.publicKey,
    this.keyId,
    this.message,
  });

  bool get isValid => status == VerificationStatus.valid;
  bool get isTampered => status == VerificationStatus.tampered;
}

/// 插件签名生成器
class PluginSigner {
  /// 计算插件归档包中所有业务文件的规范化 SHA-256 摘要（排除 plugin.sig 文件）
  static List<int> calculateArchiveDigest(Archive archive) {
    final entries = archive.files
        .where((f) =>
            f.isFile &&
            f.name != 'plugin.sig' &&
            !f.name.endsWith('/plugin.sig'))
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    final buffer = BytesBuilder(copy: false);
    for (final entry in entries) {
      buffer.add(utf8.encode(entry.name));
      buffer.add(entry.content as List<int>);
    }
    return sha256.convert(buffer.toBytes()).bytes;
  }

  /// 使用 Ed25519 密钥种子对插件包计算签名并注入 `plugin.sig`
  static List<int> signPtxBytes(
    List<int> ptxBytes,
    List<int> secretKeySeed, {
    String? keyId,
  }) {
    final archive = ZipDecoder().decodeBytes(ptxBytes, verify: true);
    final digest = calculateArchiveDigest(archive);

    final pkBytes = Ed25519.getPublicKey(secretKeySeed);
    final sigBytes = Ed25519.sign(secretKeySeed, digest);

    final signature = PluginSignature(
      algorithm: 'Ed25519',
      publicKey: Ed25519.bytesToHex(pkBytes),
      signature: Ed25519.bytesToHex(sigBytes),
      keyId: keyId,
      timestamp: DateTime.now().toUtc(),
    );

    final newArchive = Archive();
    for (final file in archive.files) {
      if (file.name != 'plugin.sig') {
        newArchive.addFile(file);
      }
    }

    // 添加新的 plugin.sig 条目
    final sigJsonBytes = utf8.encode(jsonEncode(signature.toJson()));
    newArchive.addFile(ArchiveFile(
      'plugin.sig',
      sigJsonBytes.length,
      sigJsonBytes,
    ));

    final encoder = ZipEncoder();
    return encoder.encode(newArchive) ?? <int>[];
  }
}

/// 插件签名校验器
class PluginSignatureVerifier {
  /// 受信任的开发者公钥白名单（十六进制字符串集合）
  final Set<String> trustedPublicKeys;

  /// 是否强制要求数字签名（为 true 时缺少签名直接判定为失败）
  final bool requireSignature;

  const PluginSignatureVerifier({
    this.trustedPublicKeys = const {},
    this.requireSignature = false,
  });

  /// 校验 ZIP 归档字节流中的 `plugin.sig` 签名
  PluginSignatureVerificationResult verifyArchive(Archive archive) {
    final sigEntry = archive.files.cast<ArchiveFile?>().firstWhere(
          (f) =>
              f != null &&
              f.isFile &&
              (f.name == 'plugin.sig' || f.name.endsWith('/plugin.sig')),
          orElse: () => null,
        );

    if (sigEntry == null) {
      return PluginSignatureVerificationResult(
        status: requireSignature
            ? VerificationStatus.missingSignature
            : VerificationStatus.unsigned,
        message: requireSignature ? '插件包缺少必需的数字签名 (plugin.sig)' : '插件包未签名',
      );
    }

    PluginSignature sig;
    try {
      final sigContent = utf8.decode(sigEntry.content as List<int>);
      final json = jsonDecode(sigContent) as Map<String, dynamic>;
      sig = PluginSignature.fromJson(json);
    } catch (e) {
      return PluginSignatureVerificationResult(
        status: VerificationStatus.malformed,
        message: '签名文件解析失败: $e',
      );
    }

    if (sig.algorithm != 'Ed25519') {
      return PluginSignatureVerificationResult(
        status: VerificationStatus.unsupportedAlgorithm,
        message: '不支持的签名算法: ${sig.algorithm}',
      );
    }

    if (trustedPublicKeys.isNotEmpty &&
        !trustedPublicKeys.contains(sig.publicKey)) {
      return PluginSignatureVerificationResult(
        status: VerificationStatus.untrustedKey,
        publicKey: sig.publicKey,
        keyId: sig.keyId,
        message: '插件公钥不在受信任的开发者列表中: ${sig.publicKey}',
      );
    }

    try {
      final digest = PluginSigner.calculateArchiveDigest(archive);
      final pkBytes = Ed25519.hexToBytes(sig.publicKey);
      final sigBytes = Ed25519.hexToBytes(sig.signature);

      final valid = Ed25519.verify(pkBytes, digest, sigBytes);
      if (!valid) {
        return PluginSignatureVerificationResult(
          status: VerificationStatus.tampered,
          publicKey: sig.publicKey,
          keyId: sig.keyId,
          message: '数字签名验证失败：文件已被篡改或公私钥不匹配',
        );
      }

      return PluginSignatureVerificationResult(
        status: VerificationStatus.valid,
        publicKey: sig.publicKey,
        keyId: sig.keyId,
        message: '数字签名验证成功',
      );
    } catch (e) {
      return PluginSignatureVerificationResult(
        status: VerificationStatus.malformed,
        message: '签名校验过程发生异常: $e',
      );
    }
  }

  /// 校验 .ptx 归档文件字节流
  PluginSignatureVerificationResult verifyPtxBytes(List<int> bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes, verify: true);
      return verifyArchive(archive);
    } catch (e) {
      return PluginSignatureVerificationResult(
        status: VerificationStatus.malformed,
        message: 'ZIP 归档解压失败: $e',
      );
    }
  }
}
