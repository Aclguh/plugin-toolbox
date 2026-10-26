import 'package:flutter/widgets.dart';

/// DUI 组件声明式 UI 多语言国际化适配器
///
/// 根据当前 BuildContext 的 Locale 自动分发中英文字符串，
/// 消除内置交互组件（代码预览、差异对比、颜色选择器、错误边界、树形图等）中的硬编码中文。
class DuiLocalizations {
  final Locale locale;

  const DuiLocalizations(this.locale);

  /// 全局默认语言，默认为中文
  static Locale defaultLocale = const Locale('zh');

  /// 允许全局覆盖或在测试环境中强制指定语言
  static Locale? overrideLocale;

  /// 标准 Flutter 本地化委托
  static const LocalizationsDelegate<DuiLocalizations> delegate =
      _DuiLocalizationsDelegate();

  /// 获取当前上下文中的本地化适配器实例
  static DuiLocalizations of(BuildContext context) {
    if (overrideLocale != null) {
      return DuiLocalizations(overrideLocale!);
    }
    final localized =
        Localizations.of<DuiLocalizations>(context, DuiLocalizations);
    if (localized != null) {
      return localized;
    }
    return DuiLocalizations(defaultLocale);
  }

  /// 是否为中文语言环境
  bool get isZh => locale.languageCode.toLowerCase() == 'zh';

  String get copiedToClipboard => isZh ? '已复制到剪贴板' : 'Copied to clipboard';
  String get copy => isZh ? '复制代码' : 'Copy Code';
  String get diffView => isZh ? '文本比对' : 'Diff View';
  String get original => isZh ? '原始内容' : 'Original';
  String get modified => isZh ? '修改内容' : 'Modified';
  String get presetColors => isZh ? '预设调色盘' : 'Preset Colors';
  String get customColor => isZh ? '色彩通道微调' : 'Custom Channel Adjustment';
  String get renderError => isZh ? 'UI 渲染发生异常' : 'UI Render Error';
  String get noTreeData => isZh ? '无树形数据' : 'No tree data';
  String get selectColor => isZh ? '选择颜色' : 'Select Color';
  String get confirm => isZh ? '确认' : 'Confirm';
  String get cancel => isZh ? '取消' : 'Cancel';
  String get searchPlaceholder => isZh ? '搜索...' : 'Search...';
  String componentError(String type, Object error) => isZh
      ? '组件 [$type] 加载异常: $error'
      : 'Component [$type] render error: $error';
  String textTruncatedNotice(int displayed, int total) => isZh
      ? '文本过长已截断显示（展示前 $displayed / $total 字符），可通过复制获取全文'
      : 'Text truncated (showing $displayed / $total chars), copy to get full text';
  String diffTruncatedNotice(int maxChars) => isZh
      ? '文本过长已截断比对（仅对比前 $maxChars 字符）'
      : 'Text truncated for diff (comparing first $maxChars chars only)';
}

class _DuiLocalizationsDelegate
    extends LocalizationsDelegate<DuiLocalizations> {
  const _DuiLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<DuiLocalizations> load(Locale locale) async =>
      DuiLocalizations(locale);

  @override
  bool shouldReload(_DuiLocalizationsDelegate old) => false;
}
