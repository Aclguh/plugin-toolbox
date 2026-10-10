import 'package:flutter/material.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';

/// 动态 UI (DUI) 辅助解析工具集，提供类型安全容错的图标、文本样式、颜色与数值解析
class DuiUtils {
  /// 图标名称查找表：插件 JSON 中的图标名 -> Material IconData (120+ 常用 Material 图标)
  static const Map<String, IconData> _iconTable = {
    // 基础开发与扫码
    'code': Icons.code,
    'qr_code': Icons.qr_code,
    'qr_code_scanner': Icons.qr_code_scanner,
    'phone_android': Icons.phone_android,
    'arrow_downward': Icons.arrow_downward,
    'arrow_upward': Icons.arrow_upward,
    'arrow_back': Icons.arrow_back,
    'arrow_forward': Icons.arrow_forward,
    'chevron_left': Icons.chevron_left,
    'chevron_right': Icons.chevron_right,
    'swap_vert': Icons.swap_vert,
    'compare_arrows': Icons.compare_arrows,

    // 剪贴板与编辑
    'content_copy': Icons.content_copy,
    'content_paste': Icons.content_paste,
    'content_cut': Icons.content_cut,
    'select_all': Icons.select_all,
    'undo': Icons.undo,
    'redo': Icons.redo,
    'edit': Icons.edit,
    'text_fields': Icons.text_fields,
    'title': Icons.title,
    'format_bold': Icons.format_bold,
    'format_italic': Icons.format_italic,
    'format_size': Icons.format_size,

    // 系统与设置
    'settings': Icons.settings,
    'delete': Icons.delete,
    'delete_outline': Icons.delete_outline,
    'search': Icons.search,
    'check': Icons.check,
    'check_circle': Icons.check_circle,
    'close': Icons.close,
    'cancel': Icons.cancel,
    'clear': Icons.clear,
    'refresh': Icons.refresh,
    'save': Icons.save,
    'share': Icons.share,
    'info': Icons.info,
    'info_outline': Icons.info_outline,
    'help': Icons.help,
    'help_outline': Icons.help_outline,
    'warning': Icons.warning,
    'warning_amber': Icons.warning_amber,
    'error': Icons.error,
    'error_outline': Icons.error_outline,

    // 绘画与色彩
    'brush': Icons.brush,
    'draw': Icons.draw,
    'palette': Icons.palette,
    'color_lens': Icons.color_lens,
    'colorize': Icons.colorize,
    'gradient': Icons.gradient,

    // 文件与目录
    'folder': Icons.folder,
    'folder_open': Icons.folder_open,
    'file_present': Icons.file_present,
    'insert_drive_file': Icons.insert_drive_file,
    'description': Icons.description,
    'storage': Icons.storage,
    'sd_card': Icons.sd_card,
    'download': Icons.download,
    'upload': Icons.upload,
    'archive': Icons.archive,
    'unarchive': Icons.unarchive,

    // 相机与多媒体
    'camera': Icons.camera,
    'camera_alt': Icons.camera_alt,
    'image': Icons.image,
    'photo': Icons.photo,
    'photo_library': Icons.photo_library,
    'mic': Icons.mic,
    'mic_off': Icons.mic_off,
    'volume_up': Icons.volume_up,
    'volume_off': Icons.volume_off,
    'play_arrow': Icons.play_arrow,
    'pause': Icons.pause,
    'stop': Icons.stop,
    'music_note': Icons.music_note,
    'videocam': Icons.videocam,

    // 安全与认证
    'fingerprint': Icons.fingerprint,
    'lock': Icons.lock,
    'lock_open': Icons.lock_open,
    'lock_outline': Icons.lock_outline,
    'security': Icons.security,
    'shield': Icons.shield,
    'vpn_key': Icons.vpn_key,
    'key': Icons.key,
    'password': Icons.password,

    // 时间与日期
    'timer': Icons.timer,
    'timer_off': Icons.timer_off,
    'access_time': Icons.access_time,
    'schedule': Icons.schedule,
    'calendar_today': Icons.calendar_today,
    'event': Icons.event,
    'alarm': Icons.alarm,
    'hourglass_empty': Icons.hourglass_empty,
    'history': Icons.history,

    // 工具与计算
    'calculate': Icons.calculate,
    'build': Icons.build,
    'handyman': Icons.handyman,
    'construction': Icons.construction,
    'tune': Icons.tune,
    'straighten': Icons.straighten,
    'compress': Icons.compress,
    'translate': Icons.translate,
    'language': Icons.language,
    'spellcheck': Icons.spellcheck,

    // 网络与连接
    'wifi': Icons.wifi,
    'wifi_off': Icons.wifi_off,
    'bluetooth': Icons.bluetooth,
    'bluetooth_connected': Icons.bluetooth_connected,
    'bluetooth_disabled': Icons.bluetooth_disabled,
    'network_check': Icons.network_check,
    'link': Icons.link,
    'link_off': Icons.link_off,
    'cloud': Icons.cloud,
    'cloud_upload': Icons.cloud_upload,
    'cloud_download': Icons.cloud_download,
    'sync': Icons.sync,

    // 硬件感知与传感器
    'battery_full': Icons.battery_full,
    'battery_charging_full': Icons.battery_charging_full,
    'battery_alert': Icons.battery_alert,
    'flash_on': Icons.flash_on,
    'flash_off': Icons.flash_off,
    'vibration': Icons.vibration,
    'sensors': Icons.sensors,
    'speed': Icons.speed,
    'thermostat': Icons.thermostat,
    'nfc': Icons.nfc,
    'location_on': Icons.location_on,
    'location_off': Icons.location_off,
    'my_location': Icons.my_location,
    'map': Icons.map,
    'navigation': Icons.navigation,

    // 消息与通知
    'notifications': Icons.notifications,
    'notifications_active': Icons.notifications_active,
    'notifications_off': Icons.notifications_off,
    'email': Icons.email,
    'send': Icons.send,
    'message': Icons.message,
    'chat': Icons.chat,

    // 数据与展示
    'analytics': Icons.analytics,
    'bar_chart': Icons.bar_chart,
    'show_chart': Icons.show_chart,
    'pie_chart': Icons.pie_chart,
    'table_chart': Icons.table_chart,
    'visibility': Icons.visibility,
    'visibility_off': Icons.visibility_off,
  };

  /// M3 TextStyle 查找表（样式名 -> TextTheme 取值闭包），
  /// 以 static final 声明，闭包仅在类加载时创建一次
  static final Map<String, TextStyle? Function(TextTheme)> _textStyleTable = {
    'displayLarge': (t) => t.displayLarge,
    'displayMedium': (t) => t.displayMedium,
    'displaySmall': (t) => t.displaySmall,
    'headlineLarge': (t) => t.headlineLarge,
    'headlineMedium': (t) => t.headlineMedium,
    'headlineSmall': (t) => t.headlineSmall,
    'titleLarge': (t) => t.titleLarge,
    'titleMedium': (t) => t.titleMedium,
    'titleSmall': (t) => t.titleSmall,
    'bodyLarge': (t) => t.bodyLarge,
    'bodyMedium': (t) => t.bodyMedium,
    'bodySmall': (t) => t.bodySmall,
    'labelLarge': (t) => t.labelLarge,
  };

  /// 将字符串名称转换为 Material IconData，若无精确匹配则根据语义词元进行智能回退。
  static IconData parseIcon(String? iconName) {
    if (iconName == null || iconName.trim().isEmpty) return Icons.extension;
    final normalized = iconName.trim().toLowerCase().replaceAll('-', '_');
    final direct = _iconTable[normalized];
    if (direct != null) return direct;

    final tokens = normalized.split('_').where((t) => t.isNotEmpty).toList();
    bool hasToken(List<String> keywords) {
      return tokens.any((t) => keywords.any((k) => t == k || t.startsWith(k)));
    }

    if (hasToken(['timer', 'alarm', 'stopwatch'])) return Icons.timer;
    if (hasToken(['time', 'clock', 'date', 'calendar', 'sched'])) return Icons.access_time;
    if (hasToken(['lock', 'key', 'auth', 'pass', 'shield'])) return Icons.lock;
    if (hasToken(['calc', 'math'])) return Icons.calculate;
    if (hasToken(['color', 'paint', 'palette'])) return Icons.palette;
    if (hasToken(['lang', 'trans'])) return Icons.translate;
    if (hasToken(['file', 'doc'])) return Icons.description;
    if (hasToken(['folder', 'dir'])) return Icons.folder;
    if (hasToken(['check', 'done', 'ok'])) return Icons.check;
    if (hasToken(['close', 'cancel', 'delete', 'remove'])) return Icons.close;
    if (hasToken(['search', 'find'])) return Icons.search;
    if (hasToken(['edit', 'write'])) return Icons.edit;
    if (hasToken(['warn', 'alert'])) return Icons.warning;
    if (hasToken(['error', 'fail'])) return Icons.error;
    if (hasToken(['info'])) return Icons.info;
    if (hasToken(['chart', 'graph'])) return Icons.bar_chart;
    if (hasToken(['image', 'pic', 'photo'])) return Icons.image;
    if (hasToken(['tool', 'fix', 'build'])) return Icons.build;
    if (hasToken(['wifi', 'net'])) return Icons.wifi;
    if (hasToken(['blue'])) return Icons.bluetooth;

    return Icons.extension;
  }

  /// 解析 M3 TextStyle
  static TextStyle? parseTextStyle(BuildContext context, String? styleName) {
    if (styleName == null) return null;
    final accessor = _textStyleTable[styleName];
    if (accessor == null) return null;
    return accessor(Theme.of(context).textTheme);
  }

  /// 解析十六进制颜色字符串：支持 `#RGB`、`#RRGGBB` 与 `#AARRGGBB`（可省略 `#`）。
  /// 非法输入统一返回 null 交由调用方降级，绝不允许使插件页面崩溃。
  static Color? parseColor(dynamic val) {
    final hexInt = TypeConverter.parseColorHex(val);
    return hexInt == null ? null : Color(hexInt);
  }

  /// 解析 EdgeInsets；数值与字符串数字统一容错
  static EdgeInsets parsePadding(dynamic paddingVal) {
    if (paddingVal == null) return EdgeInsets.zero;
    if (paddingVal is num) return EdgeInsets.all(paddingVal.toDouble());
    if (paddingVal is String) {
      final all = tryDouble(paddingVal);
      return all != null ? EdgeInsets.all(all) : EdgeInsets.zero;
    }
    if (paddingVal is Map) {
      return EdgeInsets.only(
        left: tryDouble(paddingVal['left']) ?? 0,
        top: tryDouble(paddingVal['top']) ?? 0,
        right: tryDouble(paddingVal['right']) ?? 0,
        bottom: tryDouble(paddingVal['bottom']) ?? 0,
      );
    }
    return EdgeInsets.zero;
  }

  /// 安全数值解析：统一容忍 num / String / null 三种输入。
  static double? tryDouble(dynamic val) => TypeConverter.tryDouble(val);

  /// 安全整型解析：容忍 num / String / null
  static int? tryInt(dynamic val) => TypeConverter.tryInt(val);

  /// 安全布尔解析：容忍 bool / String（"true"）/ num（非零为真）/ null
  static bool tryBool(dynamic val, {bool fallback = false}) =>
      TypeConverter.tryBool(val, fallback: fallback);
}
