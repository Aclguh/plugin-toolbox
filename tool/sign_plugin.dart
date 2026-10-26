import 'dart:io';
import '../packages/core/lib/src/security/ed25519.dart';
import '../packages/core/lib/src/security/plugin_signature.dart';

/// 命令行数字签名工具 (Ed25519 Signer CLI)
///
/// 用法:
///   dart run tool/sign_plugin.dart generate-key
///   dart run tool/sign_plugin.dart sign `<path/to/plugin.ptx>` `<secret_key_hex>` `[keyId]`
///   dart run tool/sign_plugin.dart verify `<path/to/plugin.ptx>` `[trusted_pubkey_hex]`
void main(List<String> args) async {
  if (args.isEmpty) {
    print('用法:');
    print('  dart run tool/sign_plugin.dart generate-key');
    print(
        '  dart run tool/sign_plugin.dart sign <file.ptx> <secret_key_hex> [keyId]');
    print(
        '  dart run tool/sign_plugin.dart verify <file.ptx> [trusted_pubkey_hex]');
    exit(1);
  }

  final command = args[0].toLowerCase();

  switch (command) {
    case 'generate-key':
      final (seed, pk) = Ed25519.generateKeyPair();
      final seedHex = Ed25519.bytesToHex(seed);
      final pkHex = Ed25519.bytesToHex(pk);
      print('=== Ed25519 密钥对生成成功 ===');
      print('私钥种子 (Secret Key Seed Hex): $seedHex');
      print('公钥 (Public Key Hex):        $pkHex');
      print('提示: 请妥善离线保管私钥种子，切勿泄露或提交至公网仓库。');
      break;

    case 'sign':
      if (args.length < 3) {
        print('错误: 缺少参数。用法: sign <file.ptx> <secret_key_hex> [keyId]');
        exit(1);
      }
      final ptxPath = args[1];
      final secretKeyHex = args[2];
      final keyId = args.length >= 4 ? args[3] : null;

      final ptxFile = File(ptxPath);
      if (!ptxFile.existsSync()) {
        print('错误: 文件不存在: $ptxPath');
        exit(1);
      }

      final seedBytes = Ed25519.hexToBytes(secretKeyHex);
      final ptxBytes = await ptxFile.readAsBytes();

      final signedBytes = PluginSigner.signPtxBytes(
        ptxBytes,
        seedBytes,
        keyId: keyId,
      );

      await ptxFile.writeAsBytes(signedBytes, flush: true);
      final pkHex = Ed25519.bytesToHex(Ed25519.getPublicKey(seedBytes));
      print('=== 插件签名成功 ===');
      print('文件: $ptxPath');
      print('公钥: $pkHex');
      if (keyId != null) print('KeyId: $keyId');
      break;

    case 'verify':
      if (args.length < 2) {
        print('错误: 缺少参数。用法: verify <file.ptx> [trusted_pubkey_hex]');
        exit(1);
      }
      final ptxPath = args[1];
      final trustedKey = args.length >= 3 ? args[2] : null;

      final ptxFile = File(ptxPath);
      if (!ptxFile.existsSync()) {
        print('错误: 文件不存在: $ptxPath');
        exit(1);
      }

      final ptxBytes = await ptxFile.readAsBytes();
      final verifier = PluginSignatureVerifier(
        trustedPublicKeys: trustedKey != null ? {trustedKey} : {},
        requireSignature: true,
      );

      final result = verifier.verifyPtxBytes(ptxBytes);
      print('=== 签名校验结果 ===');
      print('状态: ${result.status.name}');
      if (result.publicKey != null) print('公钥: ${result.publicKey}');
      if (result.keyId != null) print('KeyId: ${result.keyId}');
      print('详情: ${result.message}');

      if (!result.isValid) {
        exit(2);
      }
      break;

    default:
      print('未知命令: $command');
      exit(1);
  }
}
