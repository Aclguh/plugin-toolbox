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
  String get goToStoreToInstall => 'Install from Store';

  @override
  String get importLocalPtx => 'Import local .ptx';
}
