import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// 纯 Dart 实现的标准 PBKDF2 密钥派生函数 (RFC 2898 / PKCS#5)
/// 默认使用 HMAC-SHA256 作为伪随机函数 (PRF)。
class Pbkdf2 {
  /// 派生密钥字节序列
  static Uint8List derive({
    required List<int> password,
    required List<int> salt,
    int iterations = 10000,
    int keyLength = 32,
  }) {
    if (iterations <= 0) {
      throw ArgumentError('迭代次数必须大于 0');
    }
    if (keyLength <= 0) {
      throw ArgumentError('派生密钥长度必须大于 0');
    }

    final hmac = Hmac(sha256, password);
    const hLen = 32; // SHA-256 输出 32 字节
    final l = (keyLength + hLen - 1) ~/ hLen;
    final r = keyLength - (l - 1) * hLen;

    final derived = Uint8List(keyLength);
    int derivedOffset = 0;

    for (int i = 1; i <= l; i++) {
      // U_1 = PRF(P, S || INT_32_BE(i))
      final saltWithBlock = Uint8List(salt.length + 4);
      saltWithBlock.setRange(0, salt.length, salt);
      ByteData.sublistView(saltWithBlock).setUint32(salt.length, i, Endian.big);

      var u = Uint8List.fromList(hmac.convert(saltWithBlock).bytes);
      final t = Uint8List.fromList(u);

      for (int c = 1; c < iterations; c++) {
        u = Uint8List.fromList(hmac.convert(u).bytes);
        for (int k = 0; k < hLen; k++) {
          t[k] ^= u[k];
        }
      }

      final copyLen = (i == l) ? r : hLen;
      derived.setRange(derivedOffset, derivedOffset + copyLen, t);
      derivedOffset += copyLen;
    }

    return derived;
  }

  /// 派生并输出十六进制字符串
  static String deriveHex({
    required String password,
    required String salt,
    int iterations = 10000,
    int keyLength = 32,
  }) {
    final bytes = derive(
      password: utf8.encode(password),
      salt: utf8.encode(salt),
      iterations: iterations,
      keyLength: keyLength,
    );
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
