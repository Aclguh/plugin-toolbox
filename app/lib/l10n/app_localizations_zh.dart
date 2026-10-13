// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'PluginToolbox';

  @override
  String get myTools => '我的工具';

  @override
  String get pluginStore => '插件商店';

  @override
  String get pluginManager => '插件管理';

  @override
  String get settings => '设置';

  @override
  String get appearanceAndDisplay => '外观与显示';

  @override
  String get themeMode => '主题模式';

  @override
  String get themeDark => '品牌深色（默认）';

  @override
  String get themeLight => '清新浅色';

  @override
  String get themeSystem => '跟随系统';

  @override
  String get dynamicColor => '动态取色 (Material You)';

  @override
  String get dynamicColorDesc => '跟随系统壁纸主色（开启后将覆盖品牌主题色）';

  @override
  String get autoRotateScreen => '重力旋转屏幕';

  @override
  String get autoRotateScreenDesc => '关闭时锁定竖屏，开启后跟随手机重力感应方向';

  @override
  String get about => '关于';

  @override
  String get aboutApp => '关于 PluginToolbox';

  @override
  String get aboutDesc => '万物皆插件 · Android 原生与动态扩展工具箱';

  @override
  String get author => '开发者';

  @override
  String get openSourceLicense => '开源协议';

  @override
  String get openSourceLicenseDesc => 'MIT License';

  @override
  String get install => '安装';

  @override
  String get update => '更新';

  @override
  String get uninstall => '卸载';

  @override
  String get cancel => '取消';

  @override
  String get confirm => '确认';

  @override
  String get searchHint => '搜索工具...';

  @override
  String get emptyToolsPrompt => '暂无已启用工具';

  @override
  String get goToStoreToInstall => '去插件商店安装';

  @override
  String get importLocalPtx => '导入本地 .ptx';
}
