/// 基础类型转换与颜色解析工具集（纯 Dart 领域层实现）
class TypeConverter {
  /// 安全数值解析：容忍 num / String / null
  static double? tryDouble(dynamic val) {
    if (val is num) return val.toDouble();
    if (val is String) return double.tryParse(val.trim());
    return null;
  }

  /// 安全整型解析：容忍 num / String / null
  static int? tryInt(dynamic val) {
    if (val is num) return val.toInt();
    if (val is String) return int.tryParse(val.trim());
    return null;
  }

  /// 安全布尔解析：容忍 bool / String（"true"/"false"）/ num（非零为真）/ null
  static bool tryBool(dynamic val, {bool fallback = false}) {
    if (val is bool) return val;
    if (val is num) return val != 0;
    if (val is String) {
      final s = val.trim().toLowerCase();
      if (s == 'true') return true;
      if (s == 'false') return false;
    }
    return fallback;
  }

  /// 解析十六进制颜色字符串为 32 位 ARGB 整型数值 (0xAARRGGBB)
  /// 支持 `#RGB`, `#RRGGBB` 与 `#AARRGGBB`（前缀 `#` 可省略）
  /// 无法解析或格式错误安全返回 null
  static int? parseColorHex(dynamic val) {
    if (val == null) return null;
    var hex = val.toString().trim();
    if (hex.startsWith('#')) hex = hex.substring(1);
    if (hex.length == 3) {
      final r = hex[0];
      final g = hex[1];
      final b = hex[2];
      hex = 'FF$r$r$g$g$b$b';
    } else if (hex.length == 6) {
      hex = 'FF$hex';
    } else if (hex.length != 8) {
      return null;
    }
    if (hex.contains(RegExp(r'[^0-9a-fA-F]'))) return null;
    return int.tryParse(hex, radix: 16);
  }
}
