// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'PluginToolbox';

  @override
  String get myTools => 'My Tools';

  @override
  String get pluginStore => 'Plugin Store';

  @override
  String get pluginManager => 'Plugin Manager';

  @override
  String get settings => 'Settings';

  @override
  String get appearanceAndDisplay => 'Appearance & Display';

  @override
  String get themeMode => 'Theme Mode';

  @override
  String get themeDark => 'Brand Dark (Default)';

  @override
  String get themeLight => 'Clean Light';

  @override
  String get themeSystem => 'Follow System';

  @override
  String get dynamicColor => 'Dynamic Color (Material You)';

  @override
  String get dynamicColorDesc =>
      'Adapt to wallpaper colors (overrides brand colors when enabled)';

  @override
  String get autoRotateScreen => 'Auto-rotate Screen';

  @override
  String get autoRotateScreenDesc =>
      'Lock portrait when disabled; follow sensor when enabled';

  @override
  String get about => 'About';

  @override
  String get aboutApp => 'About PluginToolbox';

  @override
  String get aboutDesc =>
      'Everything is a Plugin · Android Native & Dynamic Extensible Toolbox';

  @override
  String get author => 'Developer';

  @override
  String get openSourceLicense => 'Open Source License';

  @override
  String get openSourceLicenseDesc => 'MIT License';

  @override
  String get install => 'Install';

  @override
  String get update => 'Update';

  @override
  String get uninstall => 'Uninstall';

  @override
  String get cancel => 'Cancel';

  @override
  String get confirm => 'Confirm';

  @override
  String get searchHint => 'Search tools...';

  @override
  String get emptyToolsPrompt => 'No enabled tools yet';

  @override
  String get emptyToolsMessage =>
      'Install plugins from the store to launch them here. Long-press icons to reorder.';

  @override
  String get goToStoreToInstall => 'Install from Store';

  @override
  String get importLocalPtx => 'Import local .ptx';

  @override
  String get permissionPromptTitle => 'Permission Request';

  @override
  String permissionPromptHeader(String pluginName) {
    return 'Plugin \"$pluginName\" requests the following capability:';
  }

  @override
  String get permissionPromptExplanation =>
      'This operation requires granting permission to the plugin. Do you allow it?';

  @override
  String get deny => 'Deny';

  @override
  String get allow => 'Allow';

  @override
  String get pluginDiagnosticsTitle => 'Plugin Diagnostics & Console';

  @override
  String get tabStatus => 'Status';

  @override
  String get tabLogs => 'Console Logs';

  @override
  String get close => 'Close';

  @override
  String get basicInfoAndResources => 'Basic Info & Resource Usage';

  @override
  String get pluginId => 'Plugin ID';

  @override
  String get version => 'Version';

  @override
  String get category => 'Category';

  @override
  String get luaHeapAllocation => 'Lua VM Heap Allocation';

  @override
  String get sandboxStorageUsage => 'Sandbox Storage Usage';

  @override
  String get scanning => 'Scanning...';

  @override
  String get grantedPermissionsTitle => 'Granted Permissions';

  @override
  String get noSensitivePermissions => 'No sensitive permissions granted';

  @override
  String get operationsAndDiagnostics => 'Maintenance & Diagnostic Actions';

  @override
  String get cleanTempCache => 'Clean Temp Cache';

  @override
  String get cleanTempCacheDesc =>
      'Safely delete non-persistent temporary files under data/temp';

  @override
  String get cleanedTempCacheSuccess => 'Temporary cache cleaned successfully';

  @override
  String get reloadPlugin => 'Reload Plugin';

  @override
  String get reloadPluginDesc => 'Reset UI state and Lua runtime instance';

  @override
  String logCount(int count) {
    return '$count records total';
  }

  @override
  String get copyAll => 'Copy All';

  @override
  String get logsCopied => 'Logs copied to clipboard';

  @override
  String get clear => 'Clear';

  @override
  String get noLogsTitle => 'No Console Logs';

  @override
  String get noLogsMessage => '(Calls to print() in Lua will appear here)';

  @override
  String get auditTrailTitle => 'Security Access Audit Trail';

  @override
  String get noAuditTrail => 'No sensitive access records';

  @override
  String get exportDiagnosticReport => 'Export Diagnostic Report';

  @override
  String get exportDiagnosticReportDesc =>
      'Copy complete report including runtime status, audit trail, and persistent logs';

  @override
  String get diagnosticReportCopied => 'Diagnostic report copied to clipboard';

  @override
  String get refreshCatalogTooltip => 'Refresh plugin catalog';

  @override
  String get storeSubtitle =>
      'Browse catalog, verify permissions, and install with one tap';

  @override
  String get errorCatalogLoadFailed =>
      'Failed to load plugin catalog. Please check network and retry.';

  @override
  String get retry => 'Reload';

  @override
  String get emptyStoreTitle => 'Remote plugin catalog is empty';

  @override
  String get emptyStoreMessage =>
      'No plugins available currently. You can retry later or change repository in Settings.';

  @override
  String get storeSearchHint => 'Search plugin name, description, or author...';

  @override
  String get clearSearchTooltip => 'Clear search';

  @override
  String get allCategories => 'All Categories';

  @override
  String get allFilter => 'All';

  @override
  String get emptyFilterTitle => 'No matching plugins found';

  @override
  String get emptyFilterMessage =>
      'Try different keywords or clear the category filter.';

  @override
  String get clearFilter => 'Clear filter';

  @override
  String get installingPlugin => 'Installing plugin …';

  @override
  String downloadingAndInstalling(String name) {
    return 'Downloading and installing $name …';
  }

  @override
  String totalPluginCount(int count) {
    return '$count plugins total';
  }

  @override
  String filteredPluginCount(int total, int filtered) {
    return '$total plugins total ($filtered filtered)';
  }

  @override
  String storeSourceHeader(String source) {
    return 'Source: $source · Version from plugin-source manifest';
  }

  @override
  String skippedIncompleteEntries(int count) {
    return '$count entries skipped due to incomplete metadata';
  }

  @override
  String get updateAvailableBadge => 'Update';

  @override
  String localInstalledVersion(String version) {
    return 'Installed: $version';
  }

  @override
  String authorMeta(String author) {
    return 'Author: $author';
  }

  @override
  String volumeMeta(String size) {
    return 'Size: $size';
  }

  @override
  String permissionMeta(String permissions) {
    return 'Permissions: $permissions';
  }

  @override
  String categoryMeta(String category) {
    return 'Category: $category';
  }

  @override
  String authorPrefix(String author) {
    return 'Author $author';
  }

  @override
  String volumePrefix(String size) {
    return 'Size $size';
  }

  @override
  String permissionPrefix(String permissions) {
    return 'Permissions $permissions';
  }

  @override
  String versionRequirement(String minVersion) {
    return 'Requires host version $minVersion or higher';
  }

  @override
  String get versionNotSatisfied => 'Incompatible';

  @override
  String get upToDate => 'Up to date';

  @override
  String get none => 'None';

  @override
  String get updatePluginTitle => 'Update Plugin';

  @override
  String get installPluginTitle => 'Install Plugin';

  @override
  String get sensitivePermissionsWarningTitle => 'Sensitive Permissions Notice';

  @override
  String upgradeVersionPrompt(String oldVersion, String newVersion) {
    return 'Will replace local $oldVersion with $newVersion';
  }

  @override
  String pluginInstallSuccess(
      String name, String version, String action, String warnings) {
    return '$name v$version $action$warnings';
  }

  @override
  String get actionInstalled => 'installed';

  @override
  String get actionUpdated => 'updated';

  @override
  String invalidPackageError(String name, String message) {
    return '$name: Invalid package ($message)';
  }

  @override
  String installFailedRetry(String name) {
    return '$name: Installation failed. Please retry later';
  }

  @override
  String get importPtxFab => 'Import .ptx Plugin';

  @override
  String get managerSubtitleEmpty =>
      'Import .ptx packages to expand toolbox capabilities';

  @override
  String managerSubtitleCount(int count) {
    return '$count plugins · Long press card to uninstall';
  }

  @override
  String get emptyManagerTitle => 'No plugins yet. Tap button below to import';

  @override
  String get emptyManagerMessage =>
      'Supports selecting multiple .ptx / .zip packages at once. They will be enabled automatically.';

  @override
  String get selectLocalFile => 'Select local files';

  @override
  String get managerBannerTip =>
      'Long press card to uninstall plugin, long press left handle to drag and reorder';

  @override
  String get dynamicBadge => 'Dynamic';

  @override
  String versionPrefix(String version) {
    return 'Version: $version';
  }

  @override
  String importSuccessSnack(int count) {
    return 'Successfully imported $count plugins';
  }

  @override
  String get builtinPluginCannotDelete =>
      'Built-in plugins cannot be uninstalled';

  @override
  String pluginUninstalledSnack(String name) {
    return 'Plugin \"$name\" uninstalled';
  }

  @override
  String userCancelledUnsigned(String name) {
    return '$name: User cancelled installing unsigned plugin';
  }

  @override
  String userDeniedSensitivePermissions(String name) {
    return '$name: User denied sensitive permissions';
  }

  @override
  String errorInvalidPackage(String message) {
    return 'Invalid package: $message';
  }

  @override
  String get errorFileReadFailed =>
      'Failed to read package file. Please verify file integrity and retry.';

  @override
  String get errorUnknownInstall =>
      'Installation failed due to an unknown error. Please retry.';

  @override
  String get importSummaryTitle => 'Import Summary';

  @override
  String importSummarySuccess(int count) {
    return 'Succeeded ($count):';
  }

  @override
  String importSummaryFailed(int count) {
    return 'Failed ($count):';
  }

  @override
  String get installErrorTitle => 'Installation Failed';

  @override
  String get ok => 'OK';

  @override
  String get unsignedPluginWarningTitle => 'Unsigned Plugin Security Warning';

  @override
  String get unsignedPluginWarningHeader =>
      'Attempting to install a plugin without a developer digital signature.';

  @override
  String get unsignedPluginWarningBody =>
      'This package does not contain a digital signature (plugin.sig). Origin and integrity cannot be verified. Do you want to continue?';

  @override
  String unsignedPluginPluginLabel(String pluginName, String version) {
    return 'Plugin: $pluginName$version';
  }

  @override
  String unsignedPluginFilePrefix(String fileName) {
    return 'File: $fileName';
  }

  @override
  String get continueInstall => 'Continue Install';

  @override
  String get sensitivePermissionConfirmTitle =>
      'Sensitive Permission Confirmation';

  @override
  String sensitivePermissionConfirmHeader(String pluginName, String version) {
    return 'Plugin \"$pluginName v$version\" requests the following sensitive permissions:';
  }

  @override
  String get sensitivePermissionConfirmExplanation =>
      'Once granted, this plugin can access hardware or network resources. Please confirm if you trust this source.';

  @override
  String get denyAndCancel => 'Deny & Cancel';

  @override
  String get agreeAndInstall => 'Agree & Install';

  @override
  String get uninstallPluginTitle => 'Uninstall Plugin';

  @override
  String uninstallPluginConfirmBody(String name) {
    return 'Are you sure you want to uninstall plugin \"$name\"?\nAll associated data will be removed.';
  }

  @override
  String sandboxQuota(int quota) {
    return 'Sandbox Quota: $quota MB';
  }

  @override
  String get permissionManagement => 'Permissions';

  @override
  String get noPermissionsDeclared =>
      'This plugin does not declare any system permissions';

  @override
  String get sensitiveBadge => 'Sensitive';

  @override
  String get exportPtxButton => 'Export .ptx';

  @override
  String get done => 'Done';

  @override
  String get exportDialogTitle => 'Export Plugin Package';

  @override
  String exportSuccess(String path) {
    return 'Plugin exported to: $path';
  }

  @override
  String exportFailed(String error) {
    return 'Export failed: $error';
  }

  @override
  String get pluginsAndRepo => 'Plugins & Repository';

  @override
  String get pluginsAndRepoDesc =>
      'Source configuration for plugin catalog, affecting available store plugins';

  @override
  String get customPluginRepo => 'Custom Plugin Repository';

  @override
  String get pluginSecurityPolicy => 'Plugin Security Policy';

  @override
  String get securityModeStrict => 'Strict Security Mode';

  @override
  String get securityModeWarning => 'Security Warning Mode (Default)';

  @override
  String get securityModeDeveloper => 'Developer Mode';

  @override
  String get securityModeStrictSummary =>
      'Strict Mode (Only allow verified signed plugins)';

  @override
  String get securityModeWarningSummary =>
      'Warning Mode (Prompt warning for unsigned plugins, default)';

  @override
  String get securityModeDeveloperSummary =>
      'Developer Mode (Allow all unsigned plugins)';

  @override
  String get securityModeStrictDesc =>
      'Only allow plugins with valid Ed25519 digital signatures to prevent untrusted code';

  @override
  String get securityModeWarningDesc =>
      'Prompt security confirmation for unsigned plugins, block corrupted or tampered packages';

  @override
  String get securityModeDeveloperDesc =>
      'Allow all unsigned local packages, only block corrupted packages';
}
