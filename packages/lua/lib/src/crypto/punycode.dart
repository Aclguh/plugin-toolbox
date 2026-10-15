/// 纯 Dart 实现的标准 RFC 3492 Punycode 与 IDNA 域名编解码
class Punycode {
  static const int _base = 36;
  static const int _tMin = 1;
  static const int _tMax = 26;
  static const int _skew = 38;
  static const int _damp = 700;
  static const int _initialBias = 72;
  static const int _initialN = 128;
  static const String _delimiter = '-';

  static int _adapt(int delta, int numPoints, bool firstTime) {
    var d = firstTime ? delta ~/ _damp : delta >> 1;
    d += d ~/ numPoints;
    var k = 0;
    while (d > ((_base - _tMin) * _tMax) ~/ 2) {
      d ~/= (_base - _tMin);
      k += _base;
    }
    return k + (((_base - _tMin + 1) * d) ~/ (d + _skew));
  }

  static int _digitValue(int charCode) {
    if (charCode >= 0x30 && charCode <= 0x39) return charCode - 0x30 + 26;
    if (charCode >= 0x41 && charCode <= 0x5a) return charCode - 0x41;
    if (charCode >= 0x61 && charCode <= 0x7a) return charCode - 0x61;
    return -1;
  }

  static int _encodeDigit(int d) {
    return d + 22 + 75 * (d < 26 ? 1 : 0);
  }

  /// 单标签 Punycode 编码
  static String encodePart(String input) {
    final runes = input.runes.toList();
    final basicRunes = runes.where((c) => c < 0x80).toList();
    final output = StringBuffer();
    for (final c in basicRunes) {
      output.writeCharCode(c);
    }
    final int b = basicRunes.length;
    int h = b;
    if (b > 0) output.write(_delimiter);

    int n = _initialN;
    int delta = 0;
    int bias = _initialBias;

    while (h < runes.length) {
      int m = 0x7fffffff;
      for (final c in runes) {
        if (c >= n && c < m) m = c;
      }

      delta += (m - n) * (h + 1);
      n = m;

      for (final c in runes) {
        if (c < n) {
          delta++;
        }
        if (c == n) {
          int q = delta;
          for (int k = _base;; k += _base) {
            final t = k <= bias ? _tMin : (k >= bias + _tMax ? _tMax : k - bias);
            if (q < t) break;
            output.writeCharCode(_encodeDigit(t + ((q - t) % (_base - t))));
            q = (q - t) ~/ (_base - t);
          }
          output.writeCharCode(_encodeDigit(q));
          bias = _adapt(delta, h + 1, h == b);
          delta = 0;
          h++;
        }
      }
      delta++;
      n++;
    }
    return output.toString();
  }

  /// 单标签 Punycode 解码
  static String decodePart(String input) {
    var n = _initialN;
    var i = 0;
    var bias = _initialBias;
    final output = <int>[];

    final delimIdx = input.lastIndexOf(_delimiter);
    var pos = 0;
    if (delimIdx > 0) {
      for (pos = 0; pos < delimIdx; pos++) {
        final c = input.codeUnitAt(pos);
        if (c >= 0x80) throw const FormatException('非 ASCII 基础字符');
        output.add(c);
      }
      pos = delimIdx + 1;
    }

    while (pos < input.length) {
      final oldI = i;
      var w = 1;
      for (var k = _base;; k += _base) {
        if (pos >= input.length) throw const FormatException('非完整 Punycode 序列');
        final digit = _digitValue(input.codeUnitAt(pos++));
        if (digit < 0) throw const FormatException('非法 Punycode 字符');
        i += digit * w;
        final t = k <= bias ? _tMin : (k >= bias + _tMax ? _tMax : k - bias);
        if (digit < t) break;
        w *= (_base - t);
      }
      bias = _adapt(i - oldI, output.length + 1, oldI == 0);
      n += i ~/ (output.length + 1);
      i %= (output.length + 1);
      output.insert(i, n);
      i++;
    }
    return String.fromCharCodes(output);
  }

  /// 国际化域名 (IDN) 编码: 如 "测试.com" -> "xn--0zwm56d.com"
  static String encodeDomain(String domain) {
    final parts = domain.split('.');
    final result = <String>[];
    for (final p in parts) {
      final hasNonAscii = p.runes.any((r) => r >= 0x80);
      if (hasNonAscii) {
        result.add('xn--${encodePart(p)}');
      } else {
        result.add(p);
      }
    }
    return result.join('.');
  }

  /// 国际化域名 (IDN) 解码: 如 "xn--0zwm56d.com" -> "测试.com"
  static String decodeDomain(String domain) {
    final parts = domain.split('.');
    final result = <String>[];
    for (final p in parts) {
      if (p.toLowerCase().startsWith('xn--')) {
        try {
          result.add(decodePart(p.substring(4)));
        } catch (_) {
          result.add(p);
        }
      } else {
        result.add(p);
      }
    }
    return result.join('.');
  }
}
