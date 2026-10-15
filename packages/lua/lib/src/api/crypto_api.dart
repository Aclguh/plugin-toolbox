import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:lua_dardo/lua.dart';

import '../crypto/aes.dart';
import '../crypto/pbkdf2.dart';
import '../crypto/sm3.dart';

/// `crypto` — 安全加密与高级散列算法 API。
///
/// 提供 HMAC 消息认证码、高级散列算法 (SHA-512 / 国密 SM3)、
/// AES 对称加解密 (CBC / ECB 模式，PKCS#7 填充)、PBKDF2 密钥派生
/// 以及密码学安全随机字节生成。
class CryptoApi {
  static void bind(LuaState ls) {
    ls.newTable();

    // crypto.hmacMd5(key, message)
    ls.pushDartFunction((ls) {
      final key = ls.checkString(1) ?? '';
      final msg = ls.checkString(2) ?? '';
      final h = Hmac(md5, utf8.encode(key)).convert(utf8.encode(msg));
      ls.pushString(h.toString());
      return 1;
    });
    ls.setField(-2, 'hmacMd5');

    // crypto.hmacSha1(key, message)
    ls.pushDartFunction((ls) {
      final key = ls.checkString(1) ?? '';
      final msg = ls.checkString(2) ?? '';
      final h = Hmac(sha1, utf8.encode(key)).convert(utf8.encode(msg));
      ls.pushString(h.toString());
      return 1;
    });
    ls.setField(-2, 'hmacSha1');

    // crypto.hmacSha256(key, message)
    ls.pushDartFunction((ls) {
      final key = ls.checkString(1) ?? '';
      final msg = ls.checkString(2) ?? '';
      final h = Hmac(sha256, utf8.encode(key)).convert(utf8.encode(msg));
      ls.pushString(h.toString());
      return 1;
    });
    ls.setField(-2, 'hmacSha256');

    // crypto.sha512(message)
    ls.pushDartFunction((ls) {
      final msg = ls.checkString(1) ?? '';
      final h = sha512.convert(utf8.encode(msg));
      ls.pushString(h.toString());
      return 1;
    });
    ls.setField(-2, 'sha512');

    // crypto.sm3(message) -> hex string
    ls.pushDartFunction((ls) {
      final msg = ls.checkString(1) ?? '';
      final hex = Sm3Digest.hashHex(msg);
      ls.pushString(hex);
      return 1;
    });
    ls.setField(-2, 'sm3');

    // 辅助：规范化 AES Key (若恰好为 16/24/32 字节则直接用，否则用 SHA-256 派生 32 字节)
    Uint8List normalizeKey(String keyStr) {
      final keyBytes = utf8.encode(keyStr);
      if (keyBytes.length == 16 ||
          keyBytes.length == 24 ||
          keyBytes.length == 32) {
        return Uint8List.fromList(keyBytes);
      }
      return Uint8List.fromList(sha256.convert(keyBytes).bytes);
    }

    // 辅助：规范化 IV (16 字节)
    Uint8List normalizeIv(String? ivStr) {
      if (ivStr == null || ivStr.isEmpty) {
        return Uint8List(16);
      }
      final ivBytes = utf8.encode(ivStr);
      if (ivBytes.length == 16) {
        return Uint8List.fromList(ivBytes);
      }
      return Uint8List.fromList(md5.convert(ivBytes).bytes);
    }

    // crypto.aesEncrypt(plaintext, key [, iv, mode]) -> base64Cipher
    ls.pushDartFunction((ls) {
      final plaintext = ls.checkString(1) ?? '';
      final keyStr = ls.checkString(2) ?? '';
      final ivStr = ls.type(3) == LuaType.luaString ? ls.toStr(3) : null;
      final mode =
          ls.type(4) == LuaType.luaString ? ls.toStr(4)!.toLowerCase() : 'cbc';

      try {
        final keyBytes = normalizeKey(keyStr);
        final cipher = AesCipher(keyBytes);
        final plainBytes = Uint8List.fromList(utf8.encode(plaintext));

        Uint8List encrypted;
        if (mode == 'ecb') {
          encrypted = cipher.encryptEcb(plainBytes);
        } else {
          final ivBytes = normalizeIv(ivStr);
          encrypted = cipher.encryptCbc(plainBytes, ivBytes);
        }
        ls.pushString(base64Encode(encrypted));
        return 1;
      } catch (e) {
        ls.pushNil();
        ls.pushString(e.toString());
        return 2;
      }
    });
    ls.setField(-2, 'aesEncrypt');

    // crypto.aesDecrypt(ciphertextBase64, key [, iv, mode]) -> plaintext
    ls.pushDartFunction((ls) {
      final ciphertextBase64 = ls.checkString(1) ?? '';
      final keyStr = ls.checkString(2) ?? '';
      final ivStr = ls.type(3) == LuaType.luaString ? ls.toStr(3) : null;
      final mode =
          ls.type(4) == LuaType.luaString ? ls.toStr(4)!.toLowerCase() : 'cbc';

      try {
        final keyBytes = normalizeKey(keyStr);
        final cipher = AesCipher(keyBytes);
        final cipherBytes = Uint8List.fromList(base64Decode(ciphertextBase64));

        Uint8List decrypted;
        if (mode == 'ecb') {
          decrypted = cipher.decryptEcb(cipherBytes);
        } else {
          final ivBytes = normalizeIv(ivStr);
          decrypted = cipher.decryptCbc(cipherBytes, ivBytes);
        }
        ls.pushString(utf8.decode(decrypted));
        return 1;
      } catch (e) {
        ls.pushNil();
        ls.pushString(e.toString());
        return 2;
      }
    });
    ls.setField(-2, 'aesDecrypt');

    // crypto.pbkdf2(password, salt [, iterations, keyLength]) -> hex
    ls.pushDartFunction((ls) {
      final password = ls.checkString(1) ?? '';
      final salt = ls.checkString(2) ?? '';
      final iterations =
          (ls.type(3) == LuaType.luaNumber) ? ls.toInteger(3) : 10000;
      final keyLength =
          (ls.type(4) == LuaType.luaNumber) ? ls.toInteger(4) : 32;

      try {
        final hex = Pbkdf2.deriveHex(
          password: password,
          salt: salt,
          iterations: iterations,
          keyLength: keyLength,
        );
        ls.pushString(hex);
        return 1;
      } catch (e) {
        ls.pushNil();
        ls.pushString(e.toString());
        return 2;
      }
    });
    ls.setField(-2, 'pbkdf2');

    // crypto.randomBytes(length) -> hex string
    ls.pushDartFunction((ls) {
      final length = (ls.checkInteger(1) ?? 16).clamp(1, 1024 * 1024);
      final random = Random.secure();
      final bytes = Uint8List(length);
      for (int i = 0; i < length; i++) {
        bytes[i] = random.nextInt(256);
      }
      final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      ls.pushString(hex);
      return 1;
    });
    ls.setField(-2, 'randomBytes');

    ls.setGlobal('crypto');
  }
}
