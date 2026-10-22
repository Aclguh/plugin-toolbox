import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh')
  ];

  /// No description provided for @appTitle.
  ///
  /// In zh, this message translates to:
  /// **'PluginToolbox'**
  String get appTitle;

  /// No description provided for @myTools.
  ///
  /// In zh, this message translates to:
  /// **'我的工具'**
  String get myTools;

  /// No description provided for @pluginStore.
  ///
  /// In zh, this message translates to:
  /// **'插件商店'**
  String get pluginStore;

  /// No description provided for @pluginManager.
  ///
  /// In zh, this message translates to:
  /// **'插件管理'**
  String get pluginManager;

  /// No description provided for @settings.
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get settings;

  /// No description provided for @appearanceAndDisplay.
  ///
  /// In zh, this message translates to:
  /// **'外观与显示'**
  String get appearanceAndDisplay;

  /// No description provided for @themeMode.
  ///
  /// In zh, this message translates to:
  /// **'主题模式'**
  String get themeMode;

  /// No description provided for @themeDark.
  ///
  /// In zh, this message translates to:
  /// **'品牌深色（默认）'**
  String get themeDark;

  /// No description provided for @themeLight.
  ///
  /// In zh, this message translates to:
  /// **'清新浅色'**
  String get themeLight;

  /// No description provided for @themeSystem.
  ///
  /// In zh, this message translates to:
  /// **'跟随系统'**
  String get themeSystem;

  /// No description provided for @dynamicColor.
  ///
  /// In zh, this message translates to:
  /// **'动态取色 (Material You)'**
  String get dynamicColor;

  /// No description provided for @dynamicColorDesc.
  ///
  /// In zh, this message translates to:
  /// **'跟随系统壁纸主色（开启后将覆盖品牌主题色）'**
  String get dynamicColorDesc;

  /// No description provided for @autoRotateScreen.
  ///
  /// In zh, this message translates to:
  /// **'重力旋转屏幕'**
  String get autoRotateScreen;

  /// No description provided for @autoRotateScreenDesc.
  ///
  /// In zh, this message translates to:
  /// **'关闭时锁定竖屏，开启后跟随手机重力感应方向'**
  String get autoRotateScreenDesc;

  /// No description provided for @about.
  ///
  /// In zh, this message translates to:
  /// **'关于'**
  String get about;

  /// No description provided for @aboutApp.
  ///
  /// In zh, this message translates to:
  /// **'关于 PluginToolbox'**
  String get aboutApp;

  /// No description provided for @aboutDesc.
  ///
  /// In zh, this message translates to:
  /// **'万物皆插件 · Android 原生与动态扩展工具箱'**
  String get aboutDesc;

  /// No description provided for @author.
  ///
  /// In zh, this message translates to:
  /// **'开发者'**
  String get author;

  /// No description provided for @openSourceLicense.
  ///
  /// In zh, this message translates to:
  /// **'开源协议'**
  String get openSourceLicense;

  /// No description provided for @openSourceLicenseDesc.
  ///
  /// In zh, this message translates to:
  /// **'MIT License'**
  String get openSourceLicenseDesc;

  /// No description provided for @install.
  ///
  /// In zh, this message translates to:
  /// **'安装'**
  String get install;

  /// No description provided for @update.
  ///
  /// In zh, this message translates to:
  /// **'更新'**
  String get update;

  /// No description provided for @uninstall.
  ///
  /// In zh, this message translates to:
  /// **'卸载'**
  String get uninstall;

  /// No description provided for @cancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get cancel;

  /// No description provided for @confirm.
  ///
  /// In zh, this message translates to:
  /// **'确认'**
  String get confirm;

  /// No description provided for @searchHint.
  ///
  /// In zh, this message translates to:
  /// **'搜索工具...'**
  String get searchHint;

  /// No description provided for @emptyToolsPrompt.
  ///
  /// In zh, this message translates to:
  /// **'暂无已启用工具'**
  String get emptyToolsPrompt;

  /// No description provided for @goToStoreToInstall.
  ///
  /// In zh, this message translates to:
  /// **'去插件商店安装'**
  String get goToStoreToInstall;

  /// No description provided for @importLocalPtx.
  ///
  /// In zh, this message translates to:
  /// **'导入本地 .ptx'**
  String get importLocalPtx;

  /// No description provided for @permissionPromptTitle.
  ///
  /// In zh, this message translates to:
  /// **'权限申请提示'**
  String get permissionPromptTitle;

  /// No description provided for @permissionPromptHeader.
  ///
  /// In zh, this message translates to:
  /// **'插件「{pluginName}」正在请求使用以下能力：'**
  String permissionPromptHeader(String pluginName);

  /// No description provided for @permissionPromptExplanation.
  ///
  /// In zh, this message translates to:
  /// **'此操作需要向该插件授予对应权限。您是否同意授权？'**
  String get permissionPromptExplanation;

  /// No description provided for @deny.
  ///
  /// In zh, this message translates to:
  /// **'拒绝'**
  String get deny;

  /// No description provided for @allow.
  ///
  /// In zh, this message translates to:
  /// **'允许'**
  String get allow;

  /// No description provided for @pluginDiagnosticsTitle.
  ///
  /// In zh, this message translates to:
  /// **'插件诊断与控制台'**
  String get pluginDiagnosticsTitle;

  /// No description provided for @tabStatus.
  ///
  /// In zh, this message translates to:
  /// **'运行状态'**
  String get tabStatus;

  /// No description provided for @tabLogs.
  ///
  /// In zh, this message translates to:
  /// **'控制台日志'**
  String get tabLogs;

  /// No description provided for @close.
  ///
  /// In zh, this message translates to:
  /// **'关闭'**
  String get close;

  /// No description provided for @basicInfoAndResources.
  ///
  /// In zh, this message translates to:
  /// **'基础信息与资源占用'**
  String get basicInfoAndResources;

  /// No description provided for @pluginId.
  ///
  /// In zh, this message translates to:
  /// **'插件标识 (ID)'**
  String get pluginId;

  /// No description provided for @version.
  ///
  /// In zh, this message translates to:
  /// **'版本号'**
  String get version;

  /// No description provided for @category.
  ///
  /// In zh, this message translates to:
  /// **'分类'**
  String get category;

  /// No description provided for @luaHeapAllocation.
  ///
  /// In zh, this message translates to:
  /// **'Lua 虚拟机堆分配'**
  String get luaHeapAllocation;

  /// No description provided for @sandboxStorageUsage.
  ///
  /// In zh, this message translates to:
  /// **'沙箱存储占用'**
  String get sandboxStorageUsage;

  /// No description provided for @scanning.
  ///
  /// In zh, this message translates to:
  /// **'扫描中...'**
  String get scanning;

  /// No description provided for @grantedPermissionsTitle.
  ///
  /// In zh, this message translates to:
  /// **'运行期已获授权'**
  String get grantedPermissionsTitle;

  /// No description provided for @noSensitivePermissions.
  ///
  /// In zh, this message translates to:
  /// **'未授予任何敏感权限'**
  String get noSensitivePermissions;

  /// No description provided for @operationsAndDiagnostics.
  ///
  /// In zh, this message translates to:
  /// **'运维与诊断操作'**
  String get operationsAndDiagnostics;

  /// No description provided for @cleanTempCache.
  ///
  /// In zh, this message translates to:
  /// **'清理沙箱临时缓存'**
  String get cleanTempCache;

  /// No description provided for @cleanTempCacheDesc.
  ///
  /// In zh, this message translates to:
  /// **'安全清理 data/temp 目录下的非持久化缓存文件'**
  String get cleanTempCacheDesc;

  /// No description provided for @cleanedTempCacheSuccess.
  ///
  /// In zh, this message translates to:
  /// **'已清理沙箱临时缓存'**
  String get cleanedTempCacheSuccess;

  /// No description provided for @reloadPlugin.
  ///
  /// In zh, this message translates to:
  /// **'重新加载插件'**
  String get reloadPlugin;

  /// No description provided for @reloadPluginDesc.
  ///
  /// In zh, this message translates to:
  /// **'重置 UI 状态与 Lua 运行时实例'**
  String get reloadPluginDesc;

  /// No description provided for @logCount.
  ///
  /// In zh, this message translates to:
  /// **'共 {count} 条记录'**
  String logCount(int count);

  /// No description provided for @copyAll.
  ///
  /// In zh, this message translates to:
  /// **'复制全部'**
  String get copyAll;

  /// No description provided for @logsCopied.
  ///
  /// In zh, this message translates to:
  /// **'已复制日志到剪贴板'**
  String get logsCopied;

  /// No description provided for @clear.
  ///
  /// In zh, this message translates to:
  /// **'清空'**
  String get clear;

  /// No description provided for @noLogsTitle.
  ///
  /// In zh, this message translates to:
  /// **'暂无控制台日志输出'**
  String get noLogsTitle;

  /// No description provided for @noLogsMessage.
  ///
  /// In zh, this message translates to:
  /// **'(Lua 中调用 print() 会在此处显示)'**
  String get noLogsMessage;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
