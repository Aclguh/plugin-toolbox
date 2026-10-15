import 'dart:convert';
import 'package:lua_dardo/lua.dart';

import '../crypto/punycode.dart';
import '../lua_value_codec.dart';

/// `codec` — 数据格式与协议编解码 API。
///
/// 提供 Base64、URL、十六进制 (Hex/HexDump)、JWT、
/// HTML 实体以及 Punycode / 国际化域名编解码。
class CodecApi {
  static void bind(LuaState ls) {
    ls.newTable();

    // codec.base64Encode(text)
    ls.pushDartFunction((ls) {
      final text = ls.checkString(1) ?? '';
      final encoded = base64Encode(utf8.encode(text));
      ls.pushString(encoded);
      return 1;
    });
    ls.setField(-2, 'base64Encode');

    // codec.base64Decode(encoded)
    ls.pushDartFunction((ls) {
      final text = ls.checkString(1) ?? '';
      try {
        final decoded = utf8.decode(base64Decode(text));
        ls.pushString(decoded);
        return 1;
      } catch (e) {
        ls.pushNil();
        ls.pushString(e.toString());
        return 2;
      }
    });
    ls.setField(-2, 'base64Decode');

    // codec.urlEncode(text)
    ls.pushDartFunction((ls) {
      final text = ls.checkString(1) ?? '';
      ls.pushString(Uri.encodeComponent(text));
      return 1;
    });
    ls.setField(-2, 'urlEncode');

    // codec.urlDecode(encoded)
    ls.pushDartFunction((ls) {
      final text = ls.checkString(1) ?? '';
      try {
        ls.pushString(Uri.decodeComponent(text));
        return 1;
      } catch (e) {
        ls.pushNil();
        ls.pushString(e.toString());
        return 2;
      }
    });
    ls.setField(-2, 'urlDecode');

    // codec.hexEncode(text) -> hexString
    ls.pushDartFunction((ls) {
      final text = ls.checkString(1) ?? '';
      final bytes = utf8.encode(text);
      final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      ls.pushString(hex);
      return 1;
    });
    ls.setField(-2, 'hexEncode');

    // codec.hexDecode(hexString) -> text
    ls.pushDartFunction((ls) {
      final raw = (ls.checkString(1) ?? '').replaceAll(RegExp(r'\s+'), '');
      if (raw.length % 2 != 0) {
        ls.pushNil();
        ls.pushString('十六进制字符串长度必须为偶数');
        return 2;
      }
      try {
        final bytes = <int>[];
        for (int i = 0; i < raw.length; i += 2) {
          final byte = int.parse(raw.substring(i, i + 2), radix: 16);
          bytes.add(byte);
        }
        ls.pushString(utf8.decode(bytes));
        return 1;
      } catch (e) {
        ls.pushNil();
        ls.pushString(e.toString());
        return 2;
      }
    });
    ls.setField(-2, 'hexDecode');

    // codec.hexDump(text) -> formattedDumpString
    ls.pushDartFunction((ls) {
      final text = ls.checkString(1) ?? '';
      final bytes = utf8.encode(text);
      final sb = StringBuffer();

      for (int i = 0; i < bytes.length; i += 16) {
        // 偏移量 8 位十六进制
        sb.write(i.toRadixString(16).padLeft(8, '0'));
        sb.write('  ');

        // 16 字节 hex (8 字节一组，中间空格)
        for (int j = 0; j < 16; j++) {
          if (i + j < bytes.length) {
            sb.write(bytes[i + j].toRadixString(16).padLeft(2, '0'));
            sb.write(' ');
          } else {
            sb.write('   ');
          }
          if (j == 7) sb.write(' ');
        }
        sb.write(' |');

        // ASCII 显示
        for (int j = 0; j < 16; j++) {
          if (i + j < bytes.length) {
            final b = bytes[i + j];
            if (b >= 32 && b <= 126) {
              sb.writeCharCode(b);
            } else {
              sb.write('.');
            }
          }
        }
        sb.write('|\n');
      }

      ls.pushString(sb.toString().trimRight());
      return 1;
    });
    ls.setField(-2, 'hexDump');

    // codec.jwtDecode(token) -> table { header = {...}, payload = {...} }
    ls.pushDartFunction((ls) {
      final token = ls.checkString(1) ?? '';
      final parts = token.trim().split('.');
      if (parts.length < 2) {
        ls.pushNil();
        ls.pushString('非法 JWT Token 结构 (段数少于 2)');
        return 2;
      }

      String decodeBase64Url(String input) {
        var normalized = input.replaceAll('-', '+').replaceAll('_', '/');
        while (normalized.length % 4 != 0) {
          normalized += '=';
        }
        return utf8.decode(base64Decode(normalized));
      }

      try {
        final headerJson = decodeBase64Url(parts[0]);
        final payloadJson = decodeBase64Url(parts[1]);

        final headerObj = jsonDecode(headerJson);
        final payloadObj = jsonDecode(payloadJson);

        final result = {
          'header': headerObj,
          'payload': payloadObj,
          'signature': parts.length > 2 ? parts[2] : '',
        };
        LuaValueCodec.push(ls, result);
        return 1;
      } catch (e) {
        ls.pushNil();
        ls.pushString('JWT 解析失败: $e');
        return 2;
      }
    });
    ls.setField(-2, 'jwtDecode');

    // codec.htmlEntitiesEncode(text) -> encoded
    ls.pushDartFunction((ls) {
      final text = ls.checkString(1) ?? '';
      const htmlEscape = HtmlEscape(HtmlEscapeMode.unknown);
      ls.pushString(htmlEscape.convert(text));
      return 1;
    });
    ls.setField(-2, 'htmlEntitiesEncode');

    // codec.htmlEntitiesDecode(text) -> decoded
    ls.pushDartFunction((ls) {
      final text = ls.checkString(1) ?? '';
      var decoded = text
          .replaceAll('&quot;', '"')
          .replaceAll('&apos;', "'")
          .replaceAll('&#39;', "'")
          .replaceAll('&amp;', '&')
          .replaceAll('&lt;', '<')
          .replaceAll('&gt;', '>')
          .replaceAll('&nbsp;', ' ');

      // 正则匹配 &#123; 或 &#x1a;
      decoded =
          decoded.replaceAllMapped(RegExp(r'&#(x[0-9a-fA-F]+|[0-9]+);'), (m) {
        final codeStr = m.group(1)!;
        int? code;
        if (codeStr.startsWith('x') || codeStr.startsWith('X')) {
          code = int.tryParse(codeStr.substring(1), radix: 16);
        } else {
          code = int.tryParse(codeStr, radix: 10);
        }
        if (code != null && code > 0 && code <= 0x10ffff) {
          return String.fromCharCode(code);
        }
        return m.group(0)!;
      });

      ls.pushString(decoded);
      return 1;
    });
    ls.setField(-2, 'htmlEntitiesDecode');

    // codec.punycodeEncode(domain) -> asciiDomain
    ls.pushDartFunction((ls) {
      final domain = ls.checkString(1) ?? '';
      final res = Punycode.encodeDomain(domain);
      ls.pushString(res);
      return 1;
    });
    ls.setField(-2, 'punycodeEncode');

    // codec.punycodeDecode(asciiDomain) -> unicodeDomain
    ls.pushDartFunction((ls) {
      final domain = ls.checkString(1) ?? '';
      final res = Punycode.decodeDomain(domain);
      ls.pushString(res);
      return 1;
    });
    ls.setField(-2, 'punycodeDecode');

    ls.setGlobal('codec');
  }
}
