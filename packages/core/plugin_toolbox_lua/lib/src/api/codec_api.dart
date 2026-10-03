import 'dart:convert';
import 'package:lua_dardo/lua.dart';

class CodecApi {
  static void bind(LuaState ls) {
    ls.newTable();

    ls.pushDartFunction((ls) {
      final text = ls.checkString(1) ?? '';
      final encoded = base64Encode(utf8.encode(text));
      ls.pushString(encoded);
      return 1;
    });
    ls.setField(-2, 'base64Encode');

    ls.pushDartFunction((ls) {
      final text = ls.checkString(1) ?? '';
      final decoded = utf8.decode(base64Decode(text));
      ls.pushString(decoded);
      return 1;
    });
    ls.setField(-2, 'base64Decode');

    ls.pushDartFunction((ls) {
      final text = ls.checkString(1) ?? '';
      ls.pushString(Uri.encodeComponent(text));
      return 1;
    });
    ls.setField(-2, 'urlEncode');

    ls.pushDartFunction((ls) {
      final text = ls.checkString(1) ?? '';
      ls.pushString(Uri.decodeComponent(text));
      return 1;
    });
    ls.setField(-2, 'urlDecode');

    ls.setGlobal('codec');
  }
}
