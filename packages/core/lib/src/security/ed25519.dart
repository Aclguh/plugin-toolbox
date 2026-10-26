import 'dart:math';
import 'package:crypto/crypto.dart';

/// 纯 Dart 实现的 Ed25519 (RFC 8032) 椭圆曲线数字签名算法
class Ed25519 {
  static final BigInt _p = BigInt.two.pow(255) - BigInt.from(19);
  static final BigInt _q = BigInt.two.pow(252) +
      BigInt.parse('27742317777372353535851937790883648493');
  static final BigInt _d =
      (-BigInt.from(121665) * _inv(BigInt.from(121666))) % _p;
  static final BigInt _i =
      _modExp(BigInt.two, (_p - BigInt.one) ~/ BigInt.from(4), _p);

  static final List<BigInt> _b = [
    _xrecover(BigInt.from(4) * _inv(BigInt.from(5)) % _p),
    BigInt.from(4) * _inv(BigInt.from(5)) % _p,
  ];

  static BigInt _inv(BigInt x) {
    return _modExp(x, _p - BigInt.two, _p);
  }

  static BigInt _modExp(BigInt base, BigInt exp, BigInt mod) {
    var res = BigInt.one;
    var b = base % mod;
    var e = exp;
    while (e > BigInt.zero) {
      if (e.isOdd) res = (res * b) % mod;
      e = e ~/ BigInt.two;
      b = (b * b) % mod;
    }
    return res;
  }

  static BigInt _xrecover(BigInt y) {
    final xx = (y * y - BigInt.one) * _inv(_d * y * y + BigInt.one) % _p;
    var x = _modExp(xx, (_p + BigInt.from(3)) ~/ BigInt.from(8), _p);
    if ((x * x - xx) % _p != BigInt.zero) {
      x = (x * _i) % _p;
    }
    if (x.isOdd) x = _p - x;
    return x;
  }

  static List<BigInt> _edwardsAdd(List<BigInt> p1, List<BigInt> p2) {
    final x1 = p1[0], y1 = p1[1];
    final x2 = p2[0], y2 = p2[1];
    final x3 =
        (x1 * y2 + x2 * y1) * _inv(BigInt.one + _d * x1 * x2 * y1 * y2) % _p;
    final y3 =
        (y1 * y2 + x1 * x2) * _inv(BigInt.one - _d * x1 * x2 * y1 * y2) % _p;
    return [x3, y3];
  }

  static List<BigInt> _scalarMult(List<BigInt> p, BigInt e) {
    if (e == BigInt.zero) return [BigInt.zero, BigInt.one];
    var q = _scalarMult(p, e ~/ BigInt.two);
    q = _edwardsAdd(q, q);
    if (e.isOdd) {
      q = _edwardsAdd(q, p);
    }
    return q;
  }

  static List<int> _encodePoint(List<BigInt> p) {
    final x = p[0], y = p[1];
    final bits = List<int>.filled(32, 0);
    var tempY = y;
    for (var i = 0; i < 32; i++) {
      bits[i] = (tempY & BigInt.from(0xff)).toInt();
      tempY = tempY >> 8;
    }
    if (x.isOdd) {
      bits[31] |= 0x80;
    }
    return bits;
  }

  static List<BigInt>? _decodePoint(List<int> bytes) {
    if (bytes.length != 32) return null;
    var y = BigInt.zero;
    for (var i = 31; i >= 0; i--) {
      final b = (i == 31) ? (bytes[i] & 0x7f) : bytes[i];
      y = (y << 8) + BigInt.from(b);
    }
    var x = _xrecover(y);
    if ((x.isOdd ? 1 : 0) != ((bytes[31] & 0x80) != 0 ? 1 : 0)) {
      x = _p - x;
    }
    final pt = [x, y];
    final x2 = (x * x) % _p;
    final y2 = (y * y) % _p;
    final lhs = (-x2 + y2) % _p;
    final rhs = (BigInt.one + _d * x2 * y2) % _p;
    if ((lhs - rhs) % _p != BigInt.zero) return null;
    return pt;
  }

  static BigInt _decodeInt(List<int> bytes) {
    var res = BigInt.zero;
    for (var i = bytes.length - 1; i >= 0; i--) {
      res = (res << 8) + BigInt.from(bytes[i]);
    }
    return res;
  }

  static List<int> _encodeInt(BigInt val, int length) {
    final res = List<int>.filled(length, 0);
    var v = val;
    for (var i = 0; i < length; i++) {
      res[i] = (v & BigInt.from(0xff)).toInt();
      v = v >> 8;
    }
    return res;
  }

  /// 随机生成 32 字节私钥种子及其对应的公钥
  static (List<int> secretKeySeed, List<int> publicKey) generateKeyPair(
      [Random? random]) {
    final rng = random ?? Random.secure();
    final seed = List<int>.generate(32, (_) => rng.nextInt(256));
    final pk = getPublicKey(seed);
    return (seed, pk);
  }

  /// 公钥生成（由 32 字节私钥种子派生 32 字节公钥）
  static List<int> getPublicKey(List<int> secretKeySeed) {
    final h = sha512.convert(secretKeySeed).bytes;
    final aBytes = List<int>.from(h.sublist(0, 32));
    aBytes[0] &= 248;
    aBytes[31] &= 127;
    aBytes[31] |= 64;
    final a = _decodeInt(aBytes);
    final aPoint = _scalarMult(_b, a);
    return _encodePoint(aPoint);
  }

  /// 对 [message] 执行 Ed25519 数字签名，返回 64 字节签名 (R || S)
  static List<int> sign(List<int> secretKeySeed, List<int> message) {
    final h = sha512.convert(secretKeySeed).bytes;
    final aBytes = List<int>.from(h.sublist(0, 32));
    aBytes[0] &= 248;
    aBytes[31] &= 127;
    aBytes[31] |= 64;
    final a = _decodeInt(aBytes);
    final aPoint = _scalarMult(_b, a);
    final aEncoded = _encodePoint(aPoint);

    final rMsg = <int>[...h.sublist(32, 64), ...message];
    final rHash = sha512.convert(rMsg).bytes;
    final r = _decodeInt(rHash) % _q;
    final rPoint = _scalarMult(_b, r);
    final rEncoded = _encodePoint(rPoint);

    final kMsg = <int>[...rEncoded, ...aEncoded, ...message];
    final kHash = sha512.convert(kMsg).bytes;
    final k = _decodeInt(kHash) % _q;

    final s = (r + k * a) % _q;
    final sEncoded = _encodeInt(s, 32);

    return [...rEncoded, ...sEncoded];
  }

  /// 校验 [message] 的 Ed25519 数字签名 [signature] 是否匹配公钥 [publicKey]
  static bool verify(
      List<int> publicKey, List<int> message, List<int> signature) {
    if (publicKey.length != 32 || signature.length != 64) return false;
    final rBytes = signature.sublist(0, 32);
    final sBytes = signature.sublist(32, 64);

    final aPoint = _decodePoint(publicKey);
    if (aPoint == null) return false;
    final rPoint = _decodePoint(rBytes);
    if (rPoint == null) return false;

    final s = _decodeInt(sBytes);
    if (s >= _q) return false;

    final kMsg = <int>[...rBytes, ...publicKey, ...message];
    final kHash = sha512.convert(kMsg).bytes;
    final k = _decodeInt(kHash) % _q;

    final sbPoint = _scalarMult(_b, s);
    final kaPoint = _scalarMult(aPoint, k);
    final rkaPoint = _edwardsAdd(rPoint, kaPoint);

    final p1 = _encodePoint(sbPoint);
    final p2 = _encodePoint(rkaPoint);
    for (var i = 0; i < 32; i++) {
      if (p1[i] != p2[i]) return false;
    }
    return true;
  }

  /// 字节数组转十六进制字符串
  static String bytesToHex(List<int> bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  /// 十六进制字符串转字节数组
  static List<int> hexToBytes(String hex) {
    final clean = hex.trim();
    if (clean.length % 2 != 0) {
      throw FormatException('非法的十六进制字符串长度: ${clean.length}');
    }
    final bytes = <int>[];
    for (var i = 0; i < clean.length; i += 2) {
      bytes.add(int.parse(clean.substring(i, i + 2), radix: 16));
    }
    return bytes;
  }
}
