import 'dart:convert';
import 'dart:typed_data';

/// 纯 Dart 实现的标准国密 SM3 密码杂凑算法 (GM/T 0004-2012)
class Sm3Digest {
  static const List<int> _iv = [
    0x7380166f, 0x4914b2b9, 0x172442d7, 0xda8a0600,
    0xa96f30bc, 0x163138aa, 0xe38dee4d, 0xb0fb0e4e,
  ];

  static int _rotl(int x, int n) {
    n %= 32;
    return (((x << n) & 0xffffffff) | ((x >> (32 - n)) & 0xffffffff)) & 0xffffffff;
  }

  static int _p0(int x) => x ^ _rotl(x, 9) ^ _rotl(x, 17);

  static int _p1(int x) => x ^ _rotl(x, 15) ^ _rotl(x, 23);

  static int _ff(int j, int x, int y, int z) {
    if (j < 16) {
      return x ^ y ^ z;
    }
    return (x & y) | (x & z) | (y & z);
  }

  static int _gg(int j, int x, int y, int z) {
    if (j < 16) {
      return x ^ y ^ z;
    }
    return (x & y) | ((~x) & z);
  }

  static int _tj(int j) => (j < 16) ? 0x79cc4519 : 0x7a879d8a;

  /// 计算字节数组的 SM3 摘要值 (返回 32 字节)
  static Uint8List hash(List<int> message) {
    final bitLength = message.length * 8;
    // 填充
    final k = (448 - ((bitLength + 8) % 512) + 512) % 512;
    final padLength = 1 + (k ~/ 8) + 8;
    final totalLength = message.length + padLength;

    final padded = Uint8List(totalLength);
    padded.setRange(0, message.length, message);
    padded[message.length] = 0x80;

    // 最后 8 字节为大端 64 位 bit 长度
    final byteData = ByteData.sublistView(padded);
    byteData.setUint64(totalLength - 8, bitLength, Endian.big);

    final v = List<int>.from(_iv);
    final w = Uint32List(68);
    final wPrime = Uint32List(64);

    for (int i = 0; i < totalLength; i += 64) {
      // 消息扩展
      for (int j = 0; j < 16; j++) {
        w[j] = byteData.getUint32(i + j * 4, Endian.big);
      }
      for (int j = 16; j < 68; j++) {
        final tmp = w[j - 16] ^ w[j - 9] ^ _rotl(w[j - 3], 15);
        w[j] = _p1(tmp) ^ _rotl(w[j - 13], 7) ^ w[j - 6];
      }
      for (int j = 0; j < 64; j++) {
        wPrime[j] = w[j] ^ w[j + 4];
      }

      int a = v[0];
      int b = v[1];
      int c = v[2];
      int d = v[3];
      int e = v[4];
      int f = v[5];
      int g = v[6];
      int h = v[7];

      for (int j = 0; j < 64; j++) {
        final ss1 = _rotl((_rotl(a, 12) + e + _rotl(_tj(j), j)) & 0xffffffff, 7);
        final ss2 = ss1 ^ _rotl(a, 12);
        final tt1 = (_ff(j, a, b, c) + d + ss2 + wPrime[j]) & 0xffffffff;
        final tt2 = (_gg(j, e, f, g) + h + ss1 + w[j]) & 0xffffffff;

        d = c;
        c = _rotl(b, 9);
        b = a;
        a = tt1;
        h = g;
        g = _rotl(f, 19);
        f = e;
        e = _p0(tt2);
      }

      v[0] ^= a;
      v[1] ^= b;
      v[2] ^= c;
      v[3] ^= d;
      v[4] ^= e;
      v[5] ^= f;
      v[6] ^= g;
      v[7] ^= h;
    }

    final out = Uint8List(32);
    final outView = ByteData.sublistView(out);
    for (int i = 0; i < 8; i++) {
      outView.setUint32(i * 4, v[i], Endian.big);
    }
    return out;
  }

  /// 计算字符串的 SM3 十六进制散列
  static String hashHex(String message) {
    final bytes = hash(utf8.encode(message));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
