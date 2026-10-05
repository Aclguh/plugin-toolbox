import 'dart:math';
import 'package:lua_dardo/lua.dart';

/// `color` — 颜色空间计算与格式转换 API。
///
/// 支持 Hex、RGB 与 HSL 颜色空间互相转换，赋能调色板与配色小工具。
class ColorApi {
  static void bind(LuaState ls) {
    ls.newTable();

    // color.hexToRgb(hexStr) -> table { r, g, b, a } | nil
    ls.pushDartFunction((ls) {
      String hex = ls.checkString(1)?.trim() ?? '';
      if (hex.startsWith('#')) hex = hex.substring(1);

      int a = 255;
      int r = 0, g = 0, b = 0;

      if (hex.length == 3) {
        // #RGB
        r = int.tryParse(hex[0] + hex[0], radix: 16) ?? 0;
        g = int.tryParse(hex[1] + hex[1], radix: 16) ?? 0;
        b = int.tryParse(hex[2] + hex[2], radix: 16) ?? 0;
      } else if (hex.length == 6) {
        // #RRGGBB
        r = int.tryParse(hex.substring(0, 2), radix: 16) ?? 0;
        g = int.tryParse(hex.substring(2, 4), radix: 16) ?? 0;
        b = int.tryParse(hex.substring(4, 6), radix: 16) ?? 0;
      } else if (hex.length == 8) {
        // #AARRGGBB
        a = int.tryParse(hex.substring(0, 2), radix: 16) ?? 255;
        r = int.tryParse(hex.substring(2, 4), radix: 16) ?? 0;
        g = int.tryParse(hex.substring(4, 6), radix: 16) ?? 0;
        b = int.tryParse(hex.substring(6, 8), radix: 16) ?? 0;
      } else {
        ls.pushNil();
        return 1;
      }

      ls.newTable();
      ls.pushString('r');
      ls.pushInteger(r);
      ls.setTable(-3);

      ls.pushString('g');
      ls.pushInteger(g);
      ls.setTable(-3);

      ls.pushString('b');
      ls.pushInteger(b);
      ls.setTable(-3);

      ls.pushString('a');
      ls.pushInteger(a);
      ls.setTable(-3);

      return 1;
    });
    ls.setField(-2, 'hexToRgb');

    // color.rgbToHex(r, g, b [, a]) -> string
    ls.pushDartFunction((ls) {
      final r = ((ls.checkInteger(1) ?? 0).clamp(0, 255)).toInt();
      final g = ((ls.checkInteger(2) ?? 0).clamp(0, 255)).toInt();
      final b = ((ls.checkInteger(3) ?? 0).clamp(0, 255)).toInt();
      final a = ls.isNoneOrNil(4)
          ? null
          : ((ls.checkInteger(4) ?? 255).clamp(0, 255)).toInt();

      String pad(int v) => v.toRadixString(16).padLeft(2, '0').toUpperCase();
      final hex =
          a != null ? '#${pad(a)}${pad(r)}${pad(g)}${pad(b)}' : '#${pad(r)}${pad(g)}${pad(b)}';
      ls.pushString(hex);
      return 1;
    });
    ls.setField(-2, 'rgbToHex');

    // color.rgbToHsl(r, g, b) -> table { h, s, l }
    ls.pushDartFunction((ls) {
      final r = ((ls.checkInteger(1) ?? 0).clamp(0, 255)) / 255.0;
      final g = ((ls.checkInteger(2) ?? 0).clamp(0, 255)) / 255.0;
      final b = ((ls.checkInteger(3) ?? 0).clamp(0, 255)) / 255.0;

      final maxVal = max(r, max(g, b));
      final minVal = min(r, min(g, b));
      final delta = maxVal - minVal;

      double h = 0.0;
      final double l = (maxVal + minVal) / 2.0;
      final double s = delta == 0 ? 0.0 : delta / (1.0 - (2 * l - 1).abs());

      if (delta > 0) {
        if (maxVal == r) {
          h = 60 * (((g - b) / delta) % 6);
        } else if (maxVal == g) {
          h = 60 * (((b - r) / delta) + 2);
        } else {
          h = 60 * (((r - g) / delta) + 4);
        }
        if (h < 0) h += 360;
      }

      ls.newTable();
      ls.pushString('h');
      ls.pushNumber(double.parse(h.toStringAsFixed(1)));
      ls.setTable(-3);

      ls.pushString('s');
      ls.pushNumber(double.parse(s.toStringAsFixed(3)));
      ls.setTable(-3);

      ls.pushString('l');
      ls.pushNumber(double.parse(l.toStringAsFixed(3)));
      ls.setTable(-3);

      return 1;
    });
    ls.setField(-2, 'rgbToHsl');

    // color.hslToRgb(h, s, l) -> table { r, g, b }
    ls.pushDartFunction((ls) {
      double h = ls.checkNumber(1) ?? 0.0;
      final s = (ls.checkNumber(2) ?? 0.0).clamp(0.0, 1.0);
      final l = (ls.checkNumber(3) ?? 0.0).clamp(0.0, 1.0);

      h = h % 360;
      if (h < 0) h += 360;

      final c = (1.0 - (2 * l - 1).abs()) * s;
      final x = c * (1.0 - (((h / 60.0) % 2) - 1).abs());
      final m = l - c / 2.0;

      double r1 = 0, g1 = 0, b1 = 0;
      final sector = (h / 60).floor() % 6;
      switch (sector) {
        case 0:
          r1 = c;
          g1 = x;
          break;
        case 1:
          r1 = x;
          g1 = c;
          break;
        case 2:
          g1 = c;
          b1 = x;
          break;
        case 3:
          g1 = x;
          b1 = c;
          break;
        case 4:
          r1 = x;
          b1 = c;
          break;
        case 5:
          r1 = c;
          b1 = x;
          break;
      }

      final r = ((r1 + m) * 255).round().clamp(0, 255);
      final g = ((g1 + m) * 255).round().clamp(0, 255);
      final b = ((b1 + m) * 255).round().clamp(0, 255);

      ls.newTable();
      ls.pushString('r');
      ls.pushInteger(r);
      ls.setTable(-3);

      ls.pushString('g');
      ls.pushInteger(g);
      ls.setTable(-3);

      ls.pushString('b');
      ls.pushInteger(b);
      ls.setTable(-3);

      return 1;
    });
    ls.setField(-2, 'hslToRgb');

    ls.setGlobal('color');
  }
}
