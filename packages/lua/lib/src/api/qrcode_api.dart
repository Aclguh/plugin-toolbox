import 'package:lua_dardo/lua.dart';
import 'package:qr/qr.dart';

/// `qrcode` — 二维码矩阵生成 API。
///
/// 基于纯 Dart 实现标准 QR 码点阵计算，
/// 输出可无缝注入 DUI `PixelGrid` 组件的位图数据。
class QrcodeApi {
  static void bind(LuaState ls) {
    ls.newTable();

    // qrcode.matrix(text [, errorCorrectLevel]) -> table { cols, rows, data } | nil, error
    ls.pushDartFunction((ls) {
      final text = ls.checkString(1) ?? '';
      if (text.isEmpty) {
        ls.pushNil();
        ls.pushString('输入文本不能为空');
        return 2;
      }

      final ecLevelStr = ls.optString(2, 'M') ?? 'M';
      int ecLevel = QrErrorCorrectLevel.M;
      switch (ecLevelStr.toUpperCase()) {
        case 'L':
          ecLevel = QrErrorCorrectLevel.L;
          break;
        case 'Q':
          ecLevel = QrErrorCorrectLevel.Q;
          break;
        case 'H':
          ecLevel = QrErrorCorrectLevel.H;
          break;
        default:
          ecLevel = QrErrorCorrectLevel.M;
      }

      try {
        final qrCode = QrCode.fromData(
          data: text,
          errorCorrectLevel: ecLevel,
        );
        final qrImage = QrImage(qrCode);
        final size = qrImage.moduleCount;

        final buffer = StringBuffer();
        for (int r = 0; r < size; r++) {
          for (int c = 0; c < size; c++) {
            buffer.write(qrImage.isDark(r, c) ? '1' : '0');
          }
        }

        ls.newTable();
        ls.pushString('cols');
        ls.pushInteger(size);
        ls.setTable(-3);

        ls.pushString('rows');
        ls.pushInteger(size);
        ls.setTable(-3);

        ls.pushString('data');
        ls.pushString(buffer.toString());
        ls.setTable(-3);

        return 1;
      } catch (e) {
        ls.pushNil();
        ls.pushString(e.toString());
        return 2;
      }
    });
    ls.setField(-2, 'matrix');

    ls.setGlobal('qrcode');
  }
}
