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
}
