import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:lua_dardo/lua.dart';

/// `crypto` — 安全加密与散列算法 API。
///
/// 提供 HMAC 消息认证码与高级散列算法，补充基础 hash 模块。
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

    ls.setGlobal('crypto');
  }
}
