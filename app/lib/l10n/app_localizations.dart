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

  /// No description provided for @emptyToolsMessage.
  ///
  /// In zh, this message translates to:
  /// **'安装插件后即可在此快速打开；长按图标可调整排列顺序。'**
  String get emptyToolsMessage;

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

  /// No description provided for @auditTrailTitle.
  ///
  /// In zh, this message translates to:
  /// **'敏感权限访问审计'**
  String get auditTrailTitle;

  /// No description provided for @noAuditTrail.
  ///
  /// In zh, this message translates to:
  /// **'暂无敏感权限访问记录'**
  String get noAuditTrail;

  /// No description provided for @exportDiagnosticReport.
  ///
  /// In zh, this message translates to:
  /// **'导出诊断报告'**
  String get exportDiagnosticReport;

  /// No description provided for @exportDiagnosticReportDesc.
  ///
  /// In zh, this message translates to:
  /// **'复制包含运行状态、权限审计与持久化日志的完整诊断报告'**
  String get exportDiagnosticReportDesc;

  /// No description provided for @diagnosticReportCopied.
  ///
  /// In zh, this message translates to:
  /// **'已复制完整诊断报告至剪贴板'**
  String get diagnosticReportCopied;

  /// No description provided for @refreshCatalogTooltip.
  ///
  /// In zh, this message translates to:
  /// **'刷新插件目录'**
  String get refreshCatalogTooltip;

  /// No description provided for @storeSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'浏览目录、确认权限后一键安装'**
  String get storeSubtitle;

  /// No description provided for @errorCatalogLoadFailed.
  ///
  /// In zh, this message translates to:
  /// **'插件目录加载失败，请检查网络后重试'**
  String get errorCatalogLoadFailed;

  /// No description provided for @retry.
  ///
  /// In zh, this message translates to:
  /// **'重新加载'**
  String get retry;

  /// No description provided for @emptyStoreTitle.
  ///
  /// In zh, this message translates to:
  /// **'远端插件目录为空'**
  String get emptyStoreTitle;

  /// No description provided for @emptyStoreMessage.
  ///
  /// In zh, this message translates to:
  /// **'当前插件仓库暂无可安装的插件，可稍后重试或在设置中切换仓库。'**
  String get emptyStoreMessage;

  /// No description provided for @storeSearchHint.
  ///
  /// In zh, this message translates to:
  /// **'搜索插件名称、描述或作者...'**
  String get storeSearchHint;

  /// No description provided for @clearSearchTooltip.
  ///
  /// In zh, this message translates to:
  /// **'清空搜索'**
  String get clearSearchTooltip;

  /// No description provided for @allCategories.
  ///
  /// In zh, this message translates to:
  /// **'全部分类'**
  String get allCategories;

  /// No description provided for @allFilter.
  ///
  /// In zh, this message translates to:
  /// **'全部'**
  String get allFilter;

  /// No description provided for @emptyFilterTitle.
  ///
  /// In zh, this message translates to:
  /// **'未找到匹配的插件'**
  String get emptyFilterTitle;

  /// No description provided for @emptyFilterMessage.
  ///
  /// In zh, this message translates to:
  /// **'试试更换关键词，或清除当前分类筛选。'**
  String get emptyFilterMessage;

  /// No description provided for @clearFilter.
  ///
  /// In zh, this message translates to:
  /// **'清除筛选条件'**
  String get clearFilter;

  /// No description provided for @installingPlugin.
  ///
  /// In zh, this message translates to:
  /// **'正在安装插件 …'**
  String get installingPlugin;

  /// No description provided for @downloadingAndInstalling.
  ///
  /// In zh, this message translates to:
  /// **'正在下载并安装 {name} …'**
  String downloadingAndInstalling(String name);

  /// No description provided for @totalPluginCount.
  ///
  /// In zh, this message translates to:
  /// **'共 {count} 个插件'**
  String totalPluginCount(int count);

  /// No description provided for @filteredPluginCount.
  ///
  /// In zh, this message translates to:
  /// **'共 {total} 个插件 (已筛选出 {filtered} 个)'**
  String filteredPluginCount(int total, int filtered);

  /// No description provided for @storeSourceHeader.
  ///
  /// In zh, this message translates to:
  /// **'来源: {source} · 版本取自 plugin-source 清单'**
  String storeSourceHeader(String source);

  /// No description provided for @skippedIncompleteEntries.
  ///
  /// In zh, this message translates to:
  /// **'{count} 个条目元数据不完整已跳过'**
  String skippedIncompleteEntries(int count);

  /// No description provided for @updateAvailableBadge.
  ///
  /// In zh, this message translates to:
  /// **'可更新'**
  String get updateAvailableBadge;

  /// No description provided for @localInstalledVersion.
  ///
  /// In zh, this message translates to:
  /// **'本地已安装 {version}'**
  String localInstalledVersion(String version);

  /// No description provided for @authorMeta.
  ///
  /// In zh, this message translates to:
  /// **'作者: {author}'**
  String authorMeta(String author);

  /// No description provided for @volumeMeta.
  ///
  /// In zh, this message translates to:
  /// **'体积: {size}'**
  String volumeMeta(String size);

  /// No description provided for @permissionMeta.
  ///
  /// In zh, this message translates to:
  /// **'权限: {permissions}'**
  String permissionMeta(String permissions);

  /// No description provided for @categoryMeta.
  ///
  /// In zh, this message translates to:
  /// **'分类: {category}'**
  String categoryMeta(String category);

  /// No description provided for @authorPrefix.
  ///
  /// In zh, this message translates to:
  /// **'作者 {author}'**
  String authorPrefix(String author);

  /// No description provided for @volumePrefix.
  ///
  /// In zh, this message translates to:
  /// **'体积 {size}'**
  String volumePrefix(String size);

  /// No description provided for @permissionPrefix.
  ///
  /// In zh, this message translates to:
  /// **'权限 {permissions}'**
  String permissionPrefix(String permissions);

  /// No description provided for @versionRequirement.
  ///
  /// In zh, this message translates to:
  /// **'需要宿主版本 {minVersion} 及以上'**
  String versionRequirement(String minVersion);

  /// No description provided for @versionNotSatisfied.
  ///
  /// In zh, this message translates to:
  /// **'版本不满足'**
  String get versionNotSatisfied;

  /// No description provided for @upToDate.
  ///
  /// In zh, this message translates to:
  /// **'已是最新'**
  String get upToDate;

  /// No description provided for @none.
  ///
  /// In zh, this message translates to:
  /// **'无'**
  String get none;

  /// No description provided for @updatePluginTitle.
  ///
  /// In zh, this message translates to:
  /// **'更新插件'**
  String get updatePluginTitle;

  /// No description provided for @installPluginTitle.
  ///
  /// In zh, this message translates to:
  /// **'安装插件'**
  String get installPluginTitle;

  /// No description provided for @sensitivePermissionsWarningTitle.
  ///
  /// In zh, this message translates to:
  /// **'敏感权限授权提醒'**
  String get sensitivePermissionsWarningTitle;

  /// No description provided for @upgradeVersionPrompt.
  ///
  /// In zh, this message translates to:
  /// **'将把本地 {oldVersion} 覆盖为 {newVersion}'**
  String upgradeVersionPrompt(String oldVersion, String newVersion);

  /// No description provided for @pluginInstallSuccess.
  ///
  /// In zh, this message translates to:
  /// **'{name} v{version} {action}{warnings}'**
  String pluginInstallSuccess(
      String name, String version, String action, String warnings);

  /// No description provided for @actionInstalled.
  ///
  /// In zh, this message translates to:
  /// **'已安装'**
  String get actionInstalled;

  /// No description provided for @actionUpdated.
  ///
  /// In zh, this message translates to:
  /// **'已更新'**
  String get actionUpdated;

  /// No description provided for @invalidPackageError.
  ///
  /// In zh, this message translates to:
  /// **'{name}: 安装包无效 ({message})'**
  String invalidPackageError(String name, String message);

  /// No description provided for @installFailedRetry.
  ///
  /// In zh, this message translates to:
  /// **'{name}: 安装失败，请稍后重试'**
  String installFailedRetry(String name);

  /// No description provided for @importPtxFab.
  ///
  /// In zh, this message translates to:
  /// **'导入 .ptx 插件'**
  String get importPtxFab;

  /// No description provided for @managerSubtitleEmpty.
  ///
  /// In zh, this message translates to:
  /// **'导入 .ptx 插件包以扩展工具箱能力'**
  String get managerSubtitleEmpty;

  /// No description provided for @managerSubtitleCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 个插件 · 长按卡片可卸载'**
  String managerSubtitleCount(int count);

  /// No description provided for @emptyManagerTitle.
  ///
  /// In zh, this message translates to:
  /// **'暂无插件，点击右下角按钮导入'**
  String get emptyManagerTitle;

  /// No description provided for @emptyManagerMessage.
  ///
  /// In zh, this message translates to:
  /// **'支持一次选择多个 .ptx / .zip 安装包，安装完成后将自动启用。'**
  String get emptyManagerMessage;

  /// No description provided for @selectLocalFile.
  ///
  /// In zh, this message translates to:
  /// **'从本地选择文件'**
  String get selectLocalFile;

  /// No description provided for @managerBannerTip.
  ///
  /// In zh, this message translates to:
  /// **'长按卡片可删除插件，长按左侧图标可拖动排序'**
  String get managerBannerTip;

  /// No description provided for @dynamicBadge.
  ///
  /// In zh, this message translates to:
  /// **'动态'**
  String get dynamicBadge;

  /// No description provided for @versionPrefix.
  ///
  /// In zh, this message translates to:
  /// **'版本: {version}'**
  String versionPrefix(String version);

  /// No description provided for @importSuccessSnack.
  ///
  /// In zh, this message translates to:
  /// **'成功导入 {count} 个插件'**
  String importSuccessSnack(int count);

  /// No description provided for @builtinPluginCannotDelete.
  ///
  /// In zh, this message translates to:
  /// **'内置插件无法删除'**
  String get builtinPluginCannotDelete;

  /// No description provided for @pluginUninstalledSnack.
  ///
  /// In zh, this message translates to:
  /// **'插件「{name}」已卸载'**
  String pluginUninstalledSnack(String name);

  /// No description provided for @userCancelledUnsigned.
  ///
  /// In zh, this message translates to:
  /// **'{name}: 用户取消安装未签名插件'**
  String userCancelledUnsigned(String name);

  /// No description provided for @userDeniedSensitivePermissions.
  ///
  /// In zh, this message translates to:
  /// **'{name}: 用户拒绝授权敏感权限'**
  String userDeniedSensitivePermissions(String name);

  /// No description provided for @errorInvalidPackage.
  ///
  /// In zh, this message translates to:
  /// **'安装包无效：{message}'**
  String errorInvalidPackage(String message);

  /// No description provided for @errorFileReadFailed.
  ///
  /// In zh, this message translates to:
  /// **'安装包文件读取失败，请确认文件完整后重试'**
  String get errorFileReadFailed;

  /// No description provided for @errorUnknownInstall.
  ///
  /// In zh, this message translates to:
  /// **'安装失败，发生未知错误，请重试'**
  String get errorUnknownInstall;

  /// No description provided for @importSummaryTitle.
  ///
  /// In zh, this message translates to:
  /// **'导入结果'**
  String get importSummaryTitle;

  /// No description provided for @importSummarySuccess.
  ///
  /// In zh, this message translates to:
  /// **'成功 {count} 个:'**
  String importSummarySuccess(int count);

  /// No description provided for @importSummaryFailed.
  ///
  /// In zh, this message translates to:
  /// **'失败 {count} 个:'**
  String importSummaryFailed(int count);

  /// No description provided for @installErrorTitle.
  ///
  /// In zh, this message translates to:
  /// **'安装失败'**
  String get installErrorTitle;

  /// No description provided for @ok.
  ///
  /// In zh, this message translates to:
  /// **'确定'**
  String get ok;

  /// No description provided for @unsignedPluginWarningTitle.
  ///
  /// In zh, this message translates to:
  /// **'未签名插件安全提示'**
  String get unsignedPluginWarningTitle;

  /// No description provided for @unsignedPluginWarningHeader.
  ///
  /// In zh, this message translates to:
  /// **'正在尝试安装未经过开发者数字签名的插件。'**
  String get unsignedPluginWarningHeader;

  /// No description provided for @unsignedPluginWarningBody.
  ///
  /// In zh, this message translates to:
  /// **'该扩展包未包含开发者数字签名 (plugin.sig)，无法保障包体来源与完整性。确定要继续安装吗？'**
  String get unsignedPluginWarningBody;

  /// No description provided for @unsignedPluginPluginLabel.
  ///
  /// In zh, this message translates to:
  /// **'插件: {pluginName}{version}'**
  String unsignedPluginPluginLabel(String pluginName, String version);

  /// No description provided for @unsignedPluginFilePrefix.
  ///
  /// In zh, this message translates to:
  /// **'文件: {fileName}'**
  String unsignedPluginFilePrefix(String fileName);

  /// No description provided for @continueInstall.
  ///
  /// In zh, this message translates to:
  /// **'继续安装'**
  String get continueInstall;

  /// No description provided for @sensitivePermissionConfirmTitle.
  ///
  /// In zh, this message translates to:
  /// **'敏感权限授权确认'**
  String get sensitivePermissionConfirmTitle;

  /// No description provided for @sensitivePermissionConfirmHeader.
  ///
  /// In zh, this message translates to:
  /// **'插件「{pluginName} v{version}」申请了以下敏感权限：'**
  String sensitivePermissionConfirmHeader(String pluginName, String version);

  /// No description provided for @sensitivePermissionConfirmExplanation.
  ///
  /// In zh, this message translates to:
  /// **'授予后该插件可访问对应硬件或网络资源，请确认是否信任该来源。'**
  String get sensitivePermissionConfirmExplanation;

  /// No description provided for @denyAndCancel.
  ///
  /// In zh, this message translates to:
  /// **'拒绝并取消'**
  String get denyAndCancel;

  /// No description provided for @agreeAndInstall.
  ///
  /// In zh, this message translates to:
  /// **'同意并安装'**
  String get agreeAndInstall;

  /// No description provided for @uninstallPluginTitle.
  ///
  /// In zh, this message translates to:
  /// **'卸载插件'**
  String get uninstallPluginTitle;

  /// No description provided for @uninstallPluginConfirmBody.
  ///
  /// In zh, this message translates to:
  /// **'确定要卸载插件「{name}」吗？\n卸载后相关数据将被清除。'**
  String uninstallPluginConfirmBody(String name);

  /// No description provided for @sandboxQuota.
  ///
  /// In zh, this message translates to:
  /// **'沙箱配额: {quota} MB'**
  String sandboxQuota(int quota);

  /// No description provided for @permissionManagement.
  ///
  /// In zh, this message translates to:
  /// **'权限管理'**
  String get permissionManagement;

  /// No description provided for @noPermissionsDeclared.
  ///
  /// In zh, this message translates to:
  /// **'该插件未声明任何系统权限'**
  String get noPermissionsDeclared;

  /// No description provided for @sensitiveBadge.
  ///
  /// In zh, this message translates to:
  /// **'敏感'**
  String get sensitiveBadge;

  /// No description provided for @exportPtxButton.
  ///
  /// In zh, this message translates to:
  /// **'导出 .ptx'**
  String get exportPtxButton;

  /// No description provided for @done.
  ///
  /// In zh, this message translates to:
  /// **'完成'**
  String get done;

  /// No description provided for @exportDialogTitle.
  ///
  /// In zh, this message translates to:
  /// **'导出插件安装包'**
  String get exportDialogTitle;

  /// No description provided for @exportSuccess.
  ///
  /// In zh, this message translates to:
  /// **'插件已导出至: {path}'**
  String exportSuccess(String path);

  /// No description provided for @exportFailed.
  ///
  /// In zh, this message translates to:
  /// **'导出失败: {error}'**
  String exportFailed(String error);

  /// No description provided for @pluginsAndRepo.
  ///
  /// In zh, this message translates to:
  /// **'插件与仓库'**
  String get pluginsAndRepo;

  /// No description provided for @pluginsAndRepoDesc.
  ///
  /// In zh, this message translates to:
  /// **'插件目录的来源配置，影响商店可安装的插件集合'**
  String get pluginsAndRepoDesc;

  /// No description provided for @customPluginRepo.
  ///
  /// In zh, this message translates to:
  /// **'自定义插件仓库'**
  String get customPluginRepo;

  /// No description provided for @pluginSecurityPolicy.
  ///
  /// In zh, this message translates to:
  /// **'插件安全策略'**
  String get pluginSecurityPolicy;

  /// No description provided for @securityModeStrict.
  ///
  /// In zh, this message translates to:
  /// **'严格安全模式'**
  String get securityModeStrict;

  /// No description provided for @securityModeWarning.
  ///
  /// In zh, this message translates to:
  /// **'安全警示模式（默认）'**
  String get securityModeWarning;

  /// No description provided for @securityModeDeveloper.
  ///
  /// In zh, this message translates to:
  /// **'开发者模式'**
  String get securityModeDeveloper;

  /// No description provided for @securityModeStrictSummary.
  ///
  /// In zh, this message translates to:
  /// **'严格安全模式（仅允许安装受信任签名插件）'**
  String get securityModeStrictSummary;

  /// No description provided for @securityModeWarningSummary.
  ///
  /// In zh, this message translates to:
  /// **'安全警示模式（未签名插件弹窗提醒，默认）'**
  String get securityModeWarningSummary;

  /// No description provided for @securityModeDeveloperSummary.
  ///
  /// In zh, this message translates to:
  /// **'开发者模式（放行所有未签名插件）'**
  String get securityModeDeveloperSummary;

  /// No description provided for @securityModeStrictDesc.
  ///
  /// In zh, this message translates to:
  /// **'仅允许安装包含合法 Ed25519 数字签名的插件，杜绝未知来源代码'**
  String get securityModeStrictDesc;

  /// No description provided for @securityModeWarningDesc.
  ///
  /// In zh, this message translates to:
  /// **'安装未签名插件时弹出安全确认，拦截被篡改的安装包'**
  String get securityModeWarningDesc;

  /// No description provided for @securityModeDeveloperDesc.
  ///
  /// In zh, this message translates to:
  /// **'放行所有本地开发与未签名插件，仅拦截被篡改的损坏包'**
  String get securityModeDeveloperDesc;
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
