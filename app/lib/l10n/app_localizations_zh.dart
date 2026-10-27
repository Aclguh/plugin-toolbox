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
  String get emptyToolsMessage => '安装插件后即可在此快速打开；长按图标可调整排列顺序。';

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

  @override
  String get auditTrailTitle => '敏感权限访问审计';

  @override
  String get noAuditTrail => '暂无敏感权限访问记录';

  @override
  String get exportDiagnosticReport => '导出诊断报告';

  @override
  String get exportDiagnosticReportDesc => '复制包含运行状态、权限审计与持久化日志的完整诊断报告';

  @override
  String get diagnosticReportCopied => '已复制完整诊断报告至剪贴板';

  @override
  String get refreshCatalogTooltip => '刷新插件目录';

  @override
  String get storeSubtitle => '浏览目录、确认权限后一键安装';

  @override
  String get errorCatalogLoadFailed => '插件目录加载失败，请检查网络后重试';

  @override
  String get retry => '重新加载';

  @override
  String get emptyStoreTitle => '远端插件目录为空';

  @override
  String get emptyStoreMessage => '当前插件仓库暂无可安装的插件，可稍后重试或在设置中切换仓库。';

  @override
  String get storeSearchHint => '搜索插件名称、描述或作者...';

  @override
  String get clearSearchTooltip => '清空搜索';

  @override
  String get allCategories => '全部分类';

  @override
  String get allFilter => '全部';

  @override
  String get emptyFilterTitle => '未找到匹配的插件';

  @override
  String get emptyFilterMessage => '试试更换关键词，或清除当前分类筛选。';

  @override
  String get clearFilter => '清除筛选条件';

  @override
  String get installingPlugin => '正在安装插件 …';

  @override
  String downloadingAndInstalling(String name) {
    return '正在下载并安装 $name …';
  }

  @override
  String totalPluginCount(int count) {
    return '共 $count 个插件';
  }

  @override
  String filteredPluginCount(int total, int filtered) {
    return '共 $total 个插件 (已筛选出 $filtered 个)';
  }

  @override
  String storeSourceHeader(String source) {
    return '来源: $source · 版本取自 plugin-source 清单';
  }

  @override
  String skippedIncompleteEntries(int count) {
    return '$count 个条目元数据不完整已跳过';
  }

  @override
  String get updateAvailableBadge => '可更新';

  @override
  String localInstalledVersion(String version) {
    return '本地已安装 $version';
  }

  @override
  String authorMeta(String author) {
    return '作者: $author';
  }

  @override
  String volumeMeta(String size) {
    return '体积: $size';
  }

  @override
  String permissionMeta(String permissions) {
    return '权限: $permissions';
  }

  @override
  String categoryMeta(String category) {
    return '分类: $category';
  }

  @override
  String authorPrefix(String author) {
    return '作者 $author';
  }

  @override
  String volumePrefix(String size) {
    return '体积 $size';
  }

  @override
  String permissionPrefix(String permissions) {
    return '权限 $permissions';
  }

  @override
  String versionRequirement(String minVersion) {
    return '需要宿主版本 $minVersion 及以上';
  }

  @override
  String get versionNotSatisfied => '版本不满足';

  @override
  String get upToDate => '已是最新';

  @override
  String get none => '无';

  @override
  String get updatePluginTitle => '更新插件';

  @override
  String get installPluginTitle => '安装插件';

  @override
  String get sensitivePermissionsWarningTitle => '敏感权限授权提醒';

  @override
  String upgradeVersionPrompt(String oldVersion, String newVersion) {
    return '将把本地 $oldVersion 覆盖为 $newVersion';
  }

  @override
  String pluginInstallSuccess(
      String name, String version, String action, String warnings) {
    return '$name v$version $action$warnings';
  }

  @override
  String get actionInstalled => '已安装';

  @override
  String get actionUpdated => '已更新';

  @override
  String invalidPackageError(String name, String message) {
    return '$name: 安装包无效 ($message)';
  }

  @override
  String installFailedRetry(String name) {
    return '$name: 安装失败，请稍后重试';
  }

  @override
  String get importPtxFab => '导入 .ptx 插件';

  @override
  String get managerSubtitleEmpty => '导入 .ptx 插件包以扩展工具箱能力';

  @override
  String managerSubtitleCount(int count) {
    return '$count 个插件 · 长按卡片可卸载';
  }

  @override
  String get emptyManagerTitle => '暂无插件，点击右下角按钮导入';

  @override
  String get emptyManagerMessage => '支持一次选择多个 .ptx / .zip 安装包，安装完成后将自动启用。';

  @override
  String get selectLocalFile => '从本地选择文件';

  @override
  String get managerBannerTip => '长按卡片可删除插件，长按左侧图标可拖动排序';

  @override
  String get dynamicBadge => '动态';

  @override
  String versionPrefix(String version) {
    return '版本: $version';
  }

  @override
  String importSuccessSnack(int count) {
    return '成功导入 $count 个插件';
  }

  @override
  String get builtinPluginCannotDelete => '内置插件无法删除';

  @override
  String pluginUninstalledSnack(String name) {
    return '插件「$name」已卸载';
  }

  @override
  String userCancelledUnsigned(String name) {
    return '$name: 用户取消安装未签名插件';
  }

  @override
  String userDeniedSensitivePermissions(String name) {
    return '$name: 用户拒绝授权敏感权限';
  }

  @override
  String errorInvalidPackage(String message) {
    return '安装包无效：$message';
  }

  @override
  String get errorFileReadFailed => '安装包文件读取失败，请确认文件完整后重试';

  @override
  String get errorUnknownInstall => '安装失败，发生未知错误，请重试';

  @override
  String get importSummaryTitle => '导入结果';

  @override
  String importSummarySuccess(int count) {
    return '成功 $count 个:';
  }

  @override
  String importSummaryFailed(int count) {
    return '失败 $count 个:';
  }

  @override
  String get installErrorTitle => '安装失败';

  @override
  String get ok => '确定';

  @override
  String get unsignedPluginWarningTitle => '未签名插件安全提示';

  @override
  String get unsignedPluginWarningHeader => '正在尝试安装未经过开发者数字签名的插件。';

  @override
  String get unsignedPluginWarningBody =>
      '该扩展包未包含开发者数字签名 (plugin.sig)，无法保障包体来源与完整性。确定要继续安装吗？';

  @override
  String unsignedPluginPluginLabel(String pluginName, String version) {
    return '插件: $pluginName$version';
  }

  @override
  String unsignedPluginFilePrefix(String fileName) {
    return '文件: $fileName';
  }

  @override
  String get continueInstall => '继续安装';

  @override
  String get sensitivePermissionConfirmTitle => '敏感权限授权确认';

  @override
  String sensitivePermissionConfirmHeader(String pluginName, String version) {
    return '插件「$pluginName v$version」申请了以下敏感权限：';
  }

  @override
  String get sensitivePermissionConfirmExplanation =>
      '授予后该插件可访问对应硬件或网络资源，请确认是否信任该来源。';

  @override
  String get denyAndCancel => '拒绝并取消';

  @override
  String get agreeAndInstall => '同意并安装';

  @override
  String get uninstallPluginTitle => '卸载插件';

  @override
  String uninstallPluginConfirmBody(String name) {
    return '确定要卸载插件「$name」吗？\n卸载后相关数据将被清除。';
  }

  @override
  String sandboxQuota(int quota) {
    return '沙箱配额: $quota MB';
  }

  @override
  String get permissionManagement => '权限管理';

  @override
  String get noPermissionsDeclared => '该插件未声明任何系统权限';

  @override
  String get sensitiveBadge => '敏感';

  @override
  String get exportPtxButton => '导出 .ptx';

  @override
  String get done => '完成';

  @override
  String get exportDialogTitle => '导出插件安装包';

  @override
  String exportSuccess(String path) {
    return '插件已导出至: $path';
  }

  @override
  String exportFailed(String error) {
    return '导出失败: $error';
  }

  @override
  String get pluginsAndRepo => '插件与仓库';

  @override
  String get pluginsAndRepoDesc => '插件目录的来源配置，影响商店可安装的插件集合';

  @override
  String get customPluginRepo => '自定义插件仓库';

  @override
  String get pluginSecurityPolicy => '插件安全策略';

  @override
  String get securityModeStrict => '严格安全模式';

  @override
  String get securityModeWarning => '安全警示模式（默认）';

  @override
  String get securityModeDeveloper => '开发者模式';

  @override
  String get securityModeStrictSummary => '严格安全模式（仅允许安装受信任签名插件）';

  @override
  String get securityModeWarningSummary => '安全警示模式（未签名插件弹窗提醒，默认）';

  @override
  String get securityModeDeveloperSummary => '开发者模式（放行所有未签名插件）';

  @override
  String get securityModeStrictDesc => '仅允许安装包含合法 Ed25519 数字签名的插件，杜绝未知来源代码';

  @override
  String get securityModeWarningDesc => '安装未签名插件时弹出安全确认，拦截被篡改的安装包';

  @override
  String get securityModeDeveloperDesc => '放行所有本地开发与未签名插件，仅拦截被篡改的损坏包';
}
