import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:lua_dardo/lua.dart';

class HashApi {
  static void bind(LuaState ls) {
    ls.newTable();
    ls.pushDartFunction((ls) {
      final text = ls.checkString(1) ?? '';
      ls.pushString(md5.convert(utf8.encode(text)).toString());
      return 1;
    });
    ls.setField(-2, 'md5');

    ls.pushDartFunction((ls) {
      final text = ls.checkString(1) ?? '';
      ls.pushString(sha1.convert(utf8.encode(text)).toString());
      return 1;
    });
    ls.setField(-2, 'sha1');

    ls.pushDartFunction((ls) {
      final text = ls.checkString(1) ?? '';
      ls.pushString(sha256.convert(utf8.encode(text)).toString());
      return 1;
    });
    ls.setField(-2, 'sha256');

    ls.setGlobal('hash');
  }
}
