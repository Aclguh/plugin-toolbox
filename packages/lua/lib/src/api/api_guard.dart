import 'package:lua_dardo/lua.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';

/// 触觉震动反馈类型枚举
enum HapticType {
  light,
  medium,
  heavy,
  selection,
  vibrate;

  static HapticType from(String? raw) {
    return switch (raw?.toLowerCase()) {
      'light' => HapticType.light,
      'medium' => HapticType.medium,
      'heavy' => HapticType.heavy,
      'selection' => HapticType.selection,
      _ => HapticType.vibrate,
    };
  }
}

/// 传感器类型枚举
enum SensorCategory {
  accelerometer,
  gyroscope,
  magnetometer,
  userAccelerometer,
  all;

  static SensorCategory? tryParse(String? raw) {
    return switch (raw?.toLowerCase()) {
      'accelerometer' => SensorCategory.accelerometer,
      'gyroscope' => SensorCategory.gyroscope,
      'magnetometer' => SensorCategory.magnetometer,
      'useraccelerometer' => SensorCategory.userAccelerometer,
      'all' => SensorCategory.all,
      _ => null,
    };
  }
}

/// 常用哈希与校验算法枚举
enum HashType {
  md5,
  sha1,
  sha256,
  sha512,
  crc32;

  static HashType? tryParse(String? raw) {
    return switch (raw?.toLowerCase()) {
      'md5' => HashType.md5,
      'sha1' => HashType.sha1,
      'sha256' => HashType.sha256,
      'sha512' => HashType.sha512,
      'crc32' => HashType.crc32,
      _ => null,
    };
  }
}

/// 宿主 API 统一权限守卫与参数校验器
class ApiGuard {
  /// 校验插件是否具备指定单项权限，未授权时抛出标准的 Lua 错误并阻断执行
  static void checkPermission(
    LuaState ls,
    PluginContext context,
    PluginPermission permission, [
    String action = 'api_call',
  ]) {
    final granted = context.hasPermission(permission, auditAction: action);
    if (!granted) {
      ls.error2('权限不足: 插件未声明 ${permission.name} 权限');
    }
  }

  /// 校验插件是否具备多项候选权限中的至少一项
  static void checkAnyPermission(
    LuaState ls,
    PluginContext context,
    List<PluginPermission> permissions, [
    String action = 'api_call',
  ]) {
    final granted = permissions.any((p) => context.hasPermission(p));
    context.recordAuditTrail(
      permissions.first,
      action,
      granted: granted,
      detail: permissions.map((p) => p.name).join('/'),
    );
    if (!granted) {
      final names = permissions.map((p) => p.name).join('/');
      ls.error2('权限不足: 插件未声明 $names 权限');
    }
  }

  /// 校验指定索引位置的参数必须为字符串，返回非空字符串
  static String checkString(LuaState ls, int index, [String? paramName]) {
    if (!ls.isString(index)) {
      final name = paramName ?? '第 $index 个参数';
      ls.error2('参数错误: $name 必须为字符串类型');
    }
    return ls.toStr(index) ?? '';
  }

  /// 获取可选字符串参数，未提供或为 nil 时返回 defaultValue
  static String? optString(LuaState ls, int index, [String? defaultValue]) {
    if (ls.isNoneOrNil(index)) return defaultValue;
    return ls.toStr(index) ?? defaultValue;
  }

  /// 校验指定索引位置必须为整数
  static int checkInt(LuaState ls, int index, [String? paramName]) {
    if (!ls.isInteger(index) && !ls.isNumber(index)) {
      final name = paramName ?? '第 $index 个参数';
      ls.error2('参数错误: $name 必须为整数');
    }
    return ls.toInteger(index);
  }

  /// 获取可选整数参数
  static int? optInt(LuaState ls, int index, [int? defaultValue]) {
    if (ls.isNoneOrNil(index)) return defaultValue;
    return ls.toInteger(index);
  }

  /// 校验指定索引位置必须为数值
  static double checkNumber(LuaState ls, int index, [String? paramName]) {
    if (!ls.isNumber(index)) {
      final name = paramName ?? '第 $index 个参数';
      ls.error2('参数错误: $name 必须为数值');
    }
    return ls.toNumber(index);
  }

  /// 获取可选数值参数
  static double? optNumber(LuaState ls, int index, [double? defaultValue]) {
    if (ls.isNoneOrNil(index)) return defaultValue;
    return ls.toNumber(index);
  }

  /// 校验指定索引位置必须为布尔类型
  static bool checkBool(LuaState ls, int index, [String? paramName]) {
    if (!ls.isBoolean(index)) {
      final name = paramName ?? '第 $index 个参数';
      ls.error2('参数错误: $name 必须为布尔类型');
    }
    return ls.toBoolean(index);
  }

  /// 获取可选布尔参数
  static bool optBool(LuaState ls, int index, [bool defaultValue = false]) {
    if (ls.isNoneOrNil(index)) return defaultValue;
    return ls.toBoolean(index);
  }

  /// 校验指定索引位置必须为 Table
  static void checkTable(LuaState ls, int index, [String? paramName]) {
    if (!ls.isTable(index)) {
      final name = paramName ?? '第 $index 个参数';
      ls.error2('参数错误: $name 必须为 Table/Object');
    }
  }
}
