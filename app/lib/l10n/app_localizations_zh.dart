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

  @override
  String get permissionPromptTitle => '权限申请提示';

  @override
  String permissionPromptHeader(String pluginName) {
    return '插件「$pluginName」正在请求使用以下能力：';
  }

  @override
  String get permissionPromptExplanation => '此操作需要向该插件授予对应权限。您是否同意授权？';

  @override
  String get deny => '拒绝';

  @override
  String get allow => '允许';

  @override
  String get pluginDiagnosticsTitle => '插件诊断与控制台';

  @override
  String get tabStatus => '运行状态';

  @override
  String get tabLogs => '控制台日志';

  @override
  String get close => '关闭';

  @override
  String get basicInfoAndResources => '基础信息与资源占用';

  @override
  String get pluginId => '插件标识 (ID)';

  @override
  String get version => '版本号';

  @override
  String get category => '分类';

  @override
  String get luaHeapAllocation => 'Lua 虚拟机堆分配';

  @override
  String get sandboxStorageUsage => '沙箱存储占用';

  @override
  String get scanning => '扫描中...';

  @override
  String get grantedPermissionsTitle => '运行期已获授权';

  @override
  String get noSensitivePermissions => '未授予任何敏感权限';

  @override
  String get operationsAndDiagnostics => '运维与诊断操作';

  @override
  String get cleanTempCache => '清理沙箱临时缓存';

  @override
  String get cleanTempCacheDesc => '安全清理 data/temp 目录下的非持久化缓存文件';

  @override
  String get cleanedTempCacheSuccess => '已清理沙箱临时缓存';

  @override
  String get reloadPlugin => '重新加载插件';

  @override
  String get reloadPluginDesc => '重置 UI 状态与 Lua 运行时实例';

  @override
  String logCount(int count) {
    return '共 $count 条记录';
  }

  @override
  String get copyAll => '复制全部';

  @override
  String get logsCopied => '已复制日志到剪贴板';

  @override
  String get clear => '清空';

  @override
  String get noLogsTitle => '暂无控制台日志输出';

  @override
  String get noLogsMessage => '(Lua 中调用 print() 会在此处显示)';
}
