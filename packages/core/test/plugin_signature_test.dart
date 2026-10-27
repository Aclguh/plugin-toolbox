import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late List<int> authorSeed;
  late List<int> authorPublicKey;
  late String authorPublicKeyHex;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('sig_test_');

    final (seed, pk) = Ed25519.generateKeyPair();
    authorSeed = seed;
    authorPublicKey = pk;
    authorPublicKeyHex = Ed25519.bytesToHex(pk);
  });

  tearDown(() async {
    try {
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  List<int> createSamplePtxBytes({String mainContent = 'print("hello")'}) {
    final archive = Archive();
    final manifestJson = jsonEncode({
      'id': 'signed_tool',
      'name': '签名测试工具',
      'version': '1.0.0',
      'description': '测试签名验签',
      'author': 'Security Team',
      'type': 'lua',
      'category': 'system',
      'entry': 'main.lua',
      'ui': 'ui/main.ui.json',
      'permissions': ['storage'],
    });

    archive.addFile(ArchiveFile(
        'plugin.json', manifestJson.length, utf8.encode(manifestJson)));
    archive.addFile(
        ArchiveFile('main.lua', mainContent.length, utf8.encode(mainContent)));
    archive.addFile(ArchiveFile('ui/main.ui.json', 2, utf8.encode('{}')));

    return ZipEncoder().encode(archive) ?? <int>[];
  }

  test('Ed25519 密钥生成、签名与验签闭环', () {
    final message =
        utf8.encode('PluginToolbox Ed25519 Signature Verification Payload');
    final signature = Ed25519.sign(authorSeed, message);

    expect(signature.length, 64);
    expect(Ed25519.verify(authorPublicKey, message, signature), isTrue);

    // 篡改数据校验失败
    final tampered =
        utf8.encode('PluginToolbox Ed25519 Signature Verification Payloax');
    expect(Ed25519.verify(authorPublicKey, tampered, signature), isFalse);

    // 伪造公钥校验失败
    final (_, roguePk) = Ed25519.generateKeyPair();
    expect(Ed25519.verify(roguePk, message, signature), isFalse);
  });

  test('PluginSigner.signPtxBytes 对 PTX 归档注入合法的 Ed25519 plugin.sig', () {
    final rawPtx = createSamplePtxBytes();
    final signedPtx = PluginSigner.signPtxBytes(
      rawPtx,
      authorSeed,
      keyId: 'key-author-01',
    );

    expect(signedPtx.length, greaterThan(rawPtx.length));

    final verifier = PluginSignatureVerifier(
      trustedPublicKeys: {authorPublicKeyHex},
      requireSignature: true,
    );

    final result = verifier.verifyPtxBytes(signedPtx);
    expect(result.isValid, isTrue);
    expect(result.status, VerificationStatus.valid);
    expect(result.publicKey, authorPublicKeyHex);
    expect(result.keyId, 'key-author-01');
  });

  test('PluginSignatureVerifier 检测内容篡改 (防供应链与中间人攻击)', () {
    final rawPtx = createSamplePtxBytes();
    final signedPtx = PluginSigner.signPtxBytes(rawPtx, authorSeed);

    // 解包并恶意篡改 main.lua
    final archive = ZipDecoder().decodeBytes(signedPtx);
    const maliciousScript = 'print("malicious payload injected")';
    final tamperedArchive = Archive();
    for (final file in archive.files) {
      if (file.name == 'main.lua') {
        tamperedArchive.addFile(ArchiveFile(
            'main.lua', maliciousScript.length, utf8.encode(maliciousScript)));
      } else {
        tamperedArchive.addFile(file);
      }
    }

    final tamperedPtx = ZipEncoder().encode(tamperedArchive)!;

    final verifier = PluginSignatureVerifier(
      trustedPublicKeys: {authorPublicKeyHex},
      requireSignature: true,
    );

    final result = verifier.verifyPtxBytes(tamperedPtx);
    expect(result.isTampered, isTrue);
    expect(result.status, VerificationStatus.tampered);
    expect(result.message, contains('篡改'));
  });

  test('PluginSignatureVerifier 拦截非受信任公钥签署的插件', () {
    final rawPtx = createSamplePtxBytes();
    // 使用非受信任的临时私钥签署
    final (untrustedSeed, _) = Ed25519.generateKeyPair();
    final signedPtx = PluginSigner.signPtxBytes(rawPtx, untrustedSeed);

    final verifier = PluginSignatureVerifier(
      trustedPublicKeys: {authorPublicKeyHex},
      requireSignature: true,
    );

    final result = verifier.verifyPtxBytes(signedPtx);
    expect(result.status, VerificationStatus.untrustedKey);
    expect(result.message, contains('不在受信任的开发者列表中'));
  });

  test('PluginInstaller.installFromPtx 在强制验签策略下验证合法包并拦截篡改包', () async {
    final rawPtx = createSamplePtxBytes();
    final signedPtx = PluginSigner.signPtxBytes(rawPtx, authorSeed);

    final signedFile = File('${tempDir.path}/valid_signed.ptx');
    await signedFile.writeAsBytes(signedPtx);

    final verifier = PluginSignatureVerifier(
      trustedPublicKeys: {authorPublicKeyHex},
      requireSignature: true,
    );

    // 1. 合法签名安装成功
    final plugin = await PluginInstaller.installFromPtx(
      signedFile,
      baseDirectory: tempDir,
      signatureVerifier: verifier,
    );

    expect(plugin.id, 'signed_tool');
    expect(plugin.manifest.name, '签名测试工具');

    // 2. 篡改包安装拦截
    final archive = ZipDecoder().decodeBytes(signedPtx);
    final tamperedArchive = Archive();
    for (final file in archive.files) {
      if (file.name == 'main.lua') {
        tamperedArchive
            .addFile(ArchiveFile('main.lua', 14, utf8.encode('evil_code()')));
      } else {
        tamperedArchive.addFile(file);
      }
    }
    final tamperedBytes = ZipEncoder().encode(tamperedArchive)!;

    final tamperedFile = File('${tempDir.path}/tampered.ptx');
    await tamperedFile.writeAsBytes(tamperedBytes);

    expect(
      () => PluginInstaller.installFromPtx(
        tamperedFile,
        baseDirectory: tempDir,
        signatureVerifier: verifier,
      ),
      throwsA(isA<FormatException>().having(
        (e) => e.message,
        'message',
        contains('数字签名校验失败'),
      )),
    );
  });

  test('inspectPluginPackage 支持关联数字签名核对并输出 Contract 结论', () {
    final rawPtx = createSamplePtxBytes();
    final signedPtx = PluginSigner.signPtxBytes(rawPtx, authorSeed);

    final verifier = PluginSignatureVerifier(
      trustedPublicKeys: {authorPublicKeyHex},
      requireSignature: true,
    );

    final contract = inspectPluginPackage(
      Uint8List.fromList(signedPtx),
      signatureVerifier: verifier,
    );

    expect(contract.isConsistent, isTrue);
    expect(contract.hasValidSignature, isTrue);
    expect(contract.signatureResult?.publicKey, authorPublicKeyHex);
  });
}
