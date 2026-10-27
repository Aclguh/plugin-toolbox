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

  static final BigInt _two = BigInt.two;
  static final BigInt _twoD = (BigInt.two * _d) % _p;

  static final List<BigInt> _b = [
    _xrecover(BigInt.from(4) * _inv(BigInt.from(5)) % _p),
    BigInt.from(4) * _inv(BigInt.from(5)) % _p,
  ];

  static final _ExtPoint _baseExt = _ExtPoint.fromAffine(_b[0], _b[1], _p);

  static BigInt _mod(BigInt val) {
    final r = val % _p;
    return r < BigInt.zero ? r + _p : r;
  }

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

  static _ExtPoint _extAdd(_ExtPoint p1, _ExtPoint p2) {
    final a = _mod((p1.y - p1.x) * (p2.y - p2.x));
    final b = _mod((p1.y + p1.x) * (p2.y + p2.x));
    final c = _mod(_twoD * p1.t * p2.t);
    final d = _mod(_two * p1.z * p2.z);
    final e = _mod(b - a);
    final f = _mod(d - c);
    final g = _mod(d + c);
    final h = _mod(b + a);
    return _ExtPoint(
      _mod(e * f),
      _mod(g * h),
      _mod(f * g),
      _mod(e * h),
    );
  }

  static _ExtPoint _extDouble(_ExtPoint p1) {
    final a = _mod(p1.x * p1.x);
    final b = _mod(p1.y * p1.y);
    final c = _mod(_two * p1.z * p1.z);
    final d = _mod(-a);
    final sum = p1.x + p1.y;
    final e = _mod(sum * sum - a - b);
    final g = _mod(d + b);
    final f = _mod(g - c);
    final h = _mod(d - b);
    return _ExtPoint(
      _mod(e * f),
      _mod(g * h),
      _mod(f * g),
      _mod(e * h),
    );
  }

  static _ExtPoint _extScalarMult(_ExtPoint p, BigInt e) {
    var res = _ExtPoint.identity;
    var current = p;
    var scalar = e;
    while (scalar > BigInt.zero) {
      if (scalar.isOdd) {
        res = _extAdd(res, current);
      }
      current = _extDouble(current);
      scalar = scalar ~/ BigInt.two;
    }
    return res;
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
    final aPoint = _extScalarMult(_baseExt, a).toAffine(_p, _inv);
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
    final aPoint = _extScalarMult(_baseExt, a).toAffine(_p, _inv);
    final aEncoded = _encodePoint(aPoint);

    final rMsg = <int>[...h.sublist(32, 64), ...message];
    final rHash = sha512.convert(rMsg).bytes;
    final r = _decodeInt(rHash) % _q;
    final rPoint = _extScalarMult(_baseExt, r).toAffine(_p, _inv);
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

    final sbPoint = _extScalarMult(_baseExt, s).toAffine(_p, _inv);
    final aPointExt = _ExtPoint.fromAffine(aPoint[0], aPoint[1], _p);
    final kaPointExt = _extScalarMult(aPointExt, k);
    final rPointExt = _ExtPoint.fromAffine(rPoint[0], rPoint[1], _p);
    final rkaPoint = _extAdd(rPointExt, kaPointExt).toAffine(_p, _inv);

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

/// 扩展 Edwards 坐标表示点 (X : Y : Z : T)，满足 x = X/Z, y = Y/Z, T = X*Y/Z
class _ExtPoint {
  final BigInt x;
  final BigInt y;
  final BigInt z;
  final BigInt t;

  const _ExtPoint(this.x, this.y, this.z, this.t);

  static final identity =
      _ExtPoint(BigInt.zero, BigInt.one, BigInt.one, BigInt.zero);

  factory _ExtPoint.fromAffine(BigInt ax, BigInt ay, BigInt p) {
    final xMod = ax % p;
    final yMod = ay % p;
    return _ExtPoint(xMod, yMod, BigInt.one, (xMod * yMod) % p);
  }

  List<BigInt> toAffine(BigInt p, BigInt Function(BigInt) inv) {
    final zInv = inv(z);
    final ax = (x * zInv) % p;
    final ay = (y * zInv) % p;
    final rAx = ax < BigInt.zero ? ax + p : ax;
    final rAy = ay < BigInt.zero ? ay + p : ay;
    return [rAx, rAy];
  }
}
