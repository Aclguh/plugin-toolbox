import 'dart:typed_data';

/// 纯 Dart 实现的标准 AES 分组加解密 (FIPS 197)
/// 支持 AES-128 / AES-192 / AES-256，模式支持 CBC 与 ECB，填充采用 PKCS#7。
class AesCipher {
  static const int blockSize = 16;

  static const List<int> _sBox = [
    0x63, 0x7c, 0x77, 0x7b, 0xf2, 0x6b, 0x6f, 0xc5, 0x30, 0x01, 0x67, 0x2b,
    0xfe, 0xd7, 0xab, 0x76, 0xca, 0x82, 0xc9, 0x7d, 0xfa, 0x59, 0x47, 0xf0,
    0xad, 0xd4, 0xa2, 0xaf, 0x9c, 0xa4, 0x72, 0xc0, 0xb7, 0xfd, 0x93, 0x26,
    0x36, 0x3f, 0xf7, 0xcc, 0x34, 0xa5, 0xe5, 0xf1, 0x71, 0xd8, 0x31, 0x15,
    0x04, 0xc7, 0x23, 0xc3, 0x18, 0x96, 0x05, 0x9a, 0x07, 0x12, 0x80, 0xe2,
    0xeb, 0x27, 0xb2, 0x75, 0x09, 0x83, 0x2c, 0x1a, 0x1b, 0x6e, 0x5a, 0xa0,
    0x52, 0x3b, 0xd6, 0xb3, 0x29, 0xe3, 0x2f, 0x84, 0x53, 0xd1, 0x00, 0xed,
    0x20, 0xfc, 0xb1, 0x5b, 0x6a, 0xcb, 0xbe, 0x39, 0x4a, 0x4c, 0x58, 0xcf,
    0xd0, 0xef, 0xaa, 0xfb, 0x43, 0x4d, 0x33, 0x85, 0x45, 0xf9, 0x02, 0x7f,
    0x50, 0x3c, 0x9f, 0xa8, 0x51, 0xa3, 0x40, 0x8f, 0x92, 0x9d, 0x38, 0xf5,
    0xbc, 0xb6, 0xda, 0x21, 0x10, 0xff, 0xf3, 0xd2, 0xcd, 0x0c, 0x13, 0xec,
    0x5f, 0x97, 0x44, 0x17, 0xc4, 0xa7, 0x7e, 0x3d, 0x64, 0x5d, 0x19, 0x73,
    0x60, 0x81, 0x4f, 0xdc, 0x22, 0x2a, 0x90, 0x88, 0x46, 0xee, 0xb8, 0x14,
    0xde, 0x5e, 0x0b, 0xdb, 0xe0, 0x32, 0x3a, 0x0a, 0x49, 0x06, 0x24, 0x5c,
    0xc2, 0xd3, 0xac, 0x62, 0x91, 0x95, 0xe4, 0x79, 0xe7, 0xc8, 0x37, 0x6d,
    0x8d, 0xd5, 0x4e, 0xa9, 0x6c, 0x56, 0xf4, 0xea, 0x65, 0x7a, 0xae, 0x08,
    0xba, 0x78, 0x25, 0x2e, 0x1c, 0xa6, 0xb4, 0xc6, 0xe8, 0xdd, 0x74, 0x1f,
    0x4b, 0xbd, 0x8b, 0x8a, 0x70, 0x3e, 0xb5, 0x66, 0x48, 0x03, 0xf6, 0x0e,
    0x61, 0x35, 0x57, 0xb9, 0x86, 0xc1, 0x1d, 0x9e, 0xe1, 0xf8, 0x98, 0x11,
    0x69, 0xd9, 0x8e, 0x94, 0x9b, 0x1e, 0x87, 0xe9, 0xce, 0x55, 0x28, 0xdf,
    0x8c, 0xa1, 0x89, 0x0d, 0xbf, 0xe6, 0x42, 0x68, 0x41, 0x99, 0x2d, 0x0f,
    0xb0, 0x54, 0xbb, 0x16,
  ];

  static final List<int> _invSBox = () {
    final inv = List<int>.filled(256, 0);
    for (int i = 0; i < 256; i++) {
      inv[_sBox[i]] = i;
    }
    return inv;
  }();

  static const List<int> _rcon = [
    0x00, 0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80, 0x1b, 0x36
  ];

  final int _nk;
  final int _nr;
  late final Uint32List _w;

  AesCipher(Uint8List key)
      : _nk = key.length ~/ 4,
        _nr = (key.length ~/ 4) + 6 {
    if (key.length != 16 && key.length != 24 && key.length != 32) {
      throw ArgumentError('AES 密钥长度必须为 16、24 或 32 字节 (当前: ${key.length})');
    }
    _w = _keyExpansion(key);
  }

  Uint32List _keyExpansion(Uint8List key) {
    final w = Uint32List(4 * (_nr + 1));
    for (int i = 0; i < _nk; i++) {
      w[i] = (key[4 * i] << 24) |
          (key[4 * i + 1] << 16) |
          (key[4 * i + 2] << 8) |
          key[4 * i + 3];
    }

    for (int i = _nk; i < 4 * (_nr + 1); i++) {
      int temp = w[i - 1];
      if (i % _nk == 0) {
        temp = _subWord(_rotWord(temp)) ^ (_rcon[i ~/ _nk] << 24);
      } else if (_nk > 6 && i % _nk == 4) {
        temp = _subWord(temp);
      }
      w[i] = w[i - _nk] ^ temp;
    }
    return w;
  }

  static int _rotWord(int word) {
    return ((word << 8) & 0xffffffff) | ((word >> 24) & 0xff);
  }

  static int _subWord(int word) {
    return (_sBox[(word >> 24) & 0xff] << 24) |
        (_sBox[(word >> 16) & 0xff] << 16) |
        (_sBox[(word >> 8) & 0xff] << 8) |
        _sBox[word & 0xff];
  }

  static int _xtime(int b) {
    return ((b << 1) ^ (((b >> 7) & 1) * 0x11b)) & 0xff;
  }

  static int _mul(int a, int b) {
    int res = 0;
    while (b > 0) {
      if ((b & 1) != 0) res ^= a;
      a = _xtime(a);
      b >>= 1;
    }
    return res;
  }

  void _encryptBlock(Uint8List input, int inOffset, Uint8List output, int outOffset) {
    final state = Uint8List(16);
    for (int i = 0; i < 16; i++) {
      state[i] = input[inOffset + i];
    }

    // AddRoundKey 0
    _addRoundKey(state, 0);

    for (int round = 1; round < _nr; round++) {
      _subBytes(state);
      _shiftRows(state);
      _mixColumns(state);
      _addRoundKey(state, round);
    }

    _subBytes(state);
    _shiftRows(state);
    _addRoundKey(state, _nr);

    for (int i = 0; i < 16; i++) {
      output[outOffset + i] = state[i];
    }
  }

  void _decryptBlock(Uint8List input, int inOffset, Uint8List output, int outOffset) {
    final state = Uint8List(16);
    for (int i = 0; i < 16; i++) {
      state[i] = input[inOffset + i];
    }

    _addRoundKey(state, _nr);

    for (int round = _nr - 1; round >= 1; round--) {
      _invShiftRows(state);
      _invSubBytes(state);
      _addRoundKey(state, round);
      _invMixColumns(state);
    }

    _invShiftRows(state);
    _invSubBytes(state);
    _addRoundKey(state, 0);

    for (int i = 0; i < 16; i++) {
      output[outOffset + i] = state[i];
    }
  }

  void _addRoundKey(Uint8List state, int round) {
    for (int c = 0; c < 4; c++) {
      final w = _w[round * 4 + c];
      state[c * 4] ^= (w >> 24) & 0xff;
      state[c * 4 + 1] ^= (w >> 16) & 0xff;
      state[c * 4 + 2] ^= (w >> 8) & 0xff;
      state[c * 4 + 3] ^= w & 0xff;
    }
  }

  void _subBytes(Uint8List state) {
    for (int i = 0; i < 16; i++) {
      state[i] = _sBox[state[i]];
    }
  }

  void _invSubBytes(Uint8List state) {
    for (int i = 0; i < 16; i++) {
      state[i] = _invSBox[state[i]];
    }
  }

  void _shiftRows(Uint8List state) {
    final t1 = state[1];
    state[1] = state[5];
    state[5] = state[9];
    state[9] = state[13];
    state[13] = t1;

    final t2 = state[2];
    final t6 = state[6];
    state[2] = state[10];
    state[6] = state[14];
    state[10] = t2;
    state[14] = t6;

    final t15 = state[15];
    state[15] = state[11];
    state[11] = state[7];
    state[7] = state[3];
    state[3] = t15;
  }

  void _invShiftRows(Uint8List state) {
    final t13 = state[13];
    state[13] = state[9];
    state[9] = state[5];
    state[5] = state[1];
    state[1] = t13;

    final t2 = state[2];
    final t6 = state[6];
    state[2] = state[10];
    state[6] = state[14];
    state[10] = t2;
    state[14] = t6;

    final t3 = state[3];
    state[3] = state[7];
    state[7] = state[11];
    state[11] = state[15];
    state[15] = t3;
  }

  void _mixColumns(Uint8List s) {
    for (int c = 0; c < 4; c++) {
      final idx = c * 4;
      final a0 = s[idx];
      final a1 = s[idx + 1];
      final a2 = s[idx + 2];
      final a3 = s[idx + 3];

      s[idx] = _xtime(a0) ^ (_xtime(a1) ^ a1) ^ a2 ^ a3;
      s[idx + 1] = a0 ^ _xtime(a1) ^ (_xtime(a2) ^ a2) ^ a3;
      s[idx + 2] = a0 ^ a1 ^ _xtime(a2) ^ (_xtime(a3) ^ a3);
      s[idx + 3] = (_xtime(a0) ^ a0) ^ a1 ^ a2 ^ _xtime(a3);
    }
  }

  void _invMixColumns(Uint8List s) {
    for (int c = 0; c < 4; c++) {
      final idx = c * 4;
      final a0 = s[idx];
      final a1 = s[idx + 1];
      final a2 = s[idx + 2];
      final a3 = s[idx + 3];

      s[idx] = _mul(0x0e, a0) ^ _mul(0x0b, a1) ^ _mul(0x0d, a2) ^ _mul(0x09, a3);
      s[idx + 1] = _mul(0x09, a0) ^ _mul(0x0e, a1) ^ _mul(0x0b, a2) ^ _mul(0x0d, a3);
      s[idx + 2] = _mul(0x0d, a0) ^ _mul(0x09, a1) ^ _mul(0x0e, a2) ^ _mul(0x0b, a3);
      s[idx + 3] = _mul(0x0b, a0) ^ _mul(0x0d, a1) ^ _mul(0x09, a2) ^ _mul(0x0e, a3);
    }
  }

  // --- 高层模式加解密 ---

  /// PKCS#7 填充
  static Uint8List padPkcs7(Uint8List data, int blockSize) {
    final padLen = blockSize - (data.length % blockSize);
    final padded = Uint8List(data.length + padLen);
    padded.setRange(0, data.length, data);
    for (int i = data.length; i < padded.length; i++) {
      padded[i] = padLen;
    }
    return padded;
  }

  /// 移除 PKCS#7 填充
  static Uint8List unpadPkcs7(Uint8List data) {
    if (data.isEmpty || data.length % blockSize != 0) {
      throw const FormatException('密文块长度非 16 字节对齐');
    }
    final padLen = data.last;
    if (padLen < 1 || padLen > blockSize || padLen > data.length) {
      throw const FormatException('非法的 PKCS#7 填充字节');
    }
    for (int i = data.length - padLen; i < data.length; i++) {
      if (data[i] != padLen) {
        throw const FormatException('损坏的 PKCS#7 填充');
      }
    }
    return Uint8List.sublistView(data, 0, data.length - padLen);
  }

  /// AES CBC 模式加密
  Uint8List encryptCbc(Uint8List plaintext, Uint8List iv, {bool padding = true}) {
    if (iv.length != blockSize) {
      throw ArgumentError('CBC IV 长度必须为 16 字节 (当前: ${iv.length})');
    }
    final input = padding ? padPkcs7(plaintext, blockSize) : plaintext;
    if (input.length % blockSize != 0) {
      throw ArgumentError('未填充时明文长度必须为 16 字节整数倍');
    }

    final output = Uint8List(input.length);
    final prevBlock = Uint8List.fromList(iv);

    for (int i = 0; i < input.length; i += blockSize) {
      final block = Uint8List(blockSize);
      for (int j = 0; j < blockSize; j++) {
        block[j] = input[i + j] ^ prevBlock[j];
      }
      _encryptBlock(block, 0, output, i);
      for (int j = 0; j < blockSize; j++) {
        prevBlock[j] = output[i + j];
      }
    }
    return output;
  }

  /// AES CBC 模式解密
  Uint8List decryptCbc(Uint8List ciphertext, Uint8List iv, {bool padding = true}) {
    if (iv.length != blockSize) {
      throw ArgumentError('CBC IV 长度必须为 16 字节 (当前: ${iv.length})');
    }
    if (ciphertext.length % blockSize != 0) {
      throw ArgumentError('密文长度必须为 16 字节整数倍');
    }

    final output = Uint8List(ciphertext.length);
    final prevBlock = Uint8List.fromList(iv);

    for (int i = 0; i < ciphertext.length; i += blockSize) {
      final decrypted = Uint8List(blockSize);
      _decryptBlock(ciphertext, i, decrypted, 0);
      for (int j = 0; j < blockSize; j++) {
        output[i + j] = decrypted[j] ^ prevBlock[j];
        prevBlock[j] = ciphertext[i + j];
      }
    }

    return padding ? unpadPkcs7(output) : output;
  }

  /// AES ECB 模式加密
  Uint8List encryptEcb(Uint8List plaintext, {bool padding = true}) {
    final input = padding ? padPkcs7(plaintext, blockSize) : plaintext;
    final output = Uint8List(input.length);
    for (int i = 0; i < input.length; i += blockSize) {
      _encryptBlock(input, i, output, i);
    }
    return output;
  }

  /// AES ECB 模式解密
  Uint8List decryptEcb(Uint8List ciphertext, {bool padding = true}) {
    if (ciphertext.length % blockSize != 0) {
      throw ArgumentError('密文长度必须为 16 字节整数倍');
    }
    final output = Uint8List(ciphertext.length);
    for (int i = 0; i < ciphertext.length; i += blockSize) {
      _decryptBlock(ciphertext, i, output, i);
    }
    return padding ? unpadPkcs7(output) : output;
  }
}
