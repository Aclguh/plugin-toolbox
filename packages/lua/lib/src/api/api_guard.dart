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
}
