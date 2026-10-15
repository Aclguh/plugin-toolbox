import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:lua_dardo/lua.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';

import '../lua_value_codec.dart';
import 'sandbox_utils.dart';

/// `i18n` — 插件多语言与国际化本地化 API。
///
/// 允许插件在沙箱根目录下的 `locales/<lang>.json` 中定义翻译字典，
/// 默认根据系统宿主环境的 Locale 自动加载，并支持参数动态插值与回退。
class I18nApi {
  static void bind(LuaState ls, PluginContext context) {
    ls.newTable();

    // 默认当前语言代码跟随系统 (如 "zh", "en")
    String currentLocale =
        PlatformDispatcher.instance.locale.languageCode.toLowerCase();
    const String defaultFallbackLocale = 'zh';

    final Map<String, Map<String, dynamic>> localeCache = {};

    Map<String, dynamic>? loadLocaleDict(String lang) {
      if (localeCache.containsKey(lang)) {
        return localeCache[lang];
      }
      try {
        final relPath = 'locales/$lang.json';
        final fullPath = resolveSandboxPath(ls, context, relPath);
        final file = File(fullPath);
        if (file.existsSync()) {
          final content = file.readAsStringSync();
          final parsed = jsonDecode(content);
          if (parsed is Map) {
            final dict = Map<String, dynamic>.from(parsed);
            localeCache[lang] = dict;
            return dict;
          }
        }
      } catch (_) {
        // 忽略非格式化或文件缺失错误
      }
      return null;
    }

    // 预热加载当前系统语言与默认回退语言
    loadLocaleDict(currentLocale);
    if (currentLocale != defaultFallbackLocale) {
      loadLocaleDict(defaultFallbackLocale);
    }

    // i18n.locale() -> string
    ls.pushDartFunction((ls) {
      ls.pushString(currentLocale);
      return 1;
    });
    ls.setField(-2, 'locale');

    // i18n.setLocale(langCode) -> bool
    ls.pushDartFunction((ls) {
      final lang = (ls.checkString(1) ?? '').trim().toLowerCase();
      if (lang.isEmpty) {
        ls.pushBoolean(false);
        return 1;
      }
      currentLocale = lang;
      loadLocaleDict(lang);
      ls.pushBoolean(true);
      return 1;
    });
    ls.setField(-2, 'setLocale');

    // i18n.t(key [, paramsTable]) -> string
    ls.pushDartFunction((ls) {
      final key = ls.checkString(1) ?? '';
      Map<dynamic, dynamic>? params;

      if (ls.type(2) == LuaType.luaTable) {
        ls.pushValue(2);
        final popped = LuaValueCodec.pop(ls);
        if (popped is Map) {
          params = popped;
        }
      }

      // 1. 在当前 locale 字典中查询
      final currentDict = loadLocaleDict(currentLocale);
      dynamic val = currentDict?[key];

      // 2. 若未命中且当前非 fallback，在 fallback 字典中查询
      if (val == null && currentLocale != defaultFallbackLocale) {
        final fallbackDict = loadLocaleDict(defaultFallbackLocale);
        val = fallbackDict?[key];
      }

      // 3. 仍未命中，尝试在 "en" 字典中查询
      if (val == null && currentLocale != 'en' && defaultFallbackLocale != 'en') {
        final enDict = loadLocaleDict('en');
        val = enDict?[key];
      }

      var text = val?.toString() ?? key;

      // 参数插值: {{name}} 或 {name}
      if (params != null && params.isNotEmpty) {
        params.forEach((k, v) {
          final strK = k.toString();
          final strV = v?.toString() ?? '';
          text = text.replaceAll('{{$strK}}', strV);
          text = text.replaceAll('{$strK}', strV);
        });
      }

      ls.pushString(text);
      return 1;
    });
    ls.setField(-2, 't');

    // i18n.allLocales() -> table (array of strings)
    ls.pushDartFunction((ls) {
      final locales = <String>[];
      try {
        final localesDirFull =
            resolveSandboxPath(ls, context, 'locales');
        final dir = Directory(localesDirFull);
        if (dir.existsSync()) {
          for (final entity in dir.listSync()) {
            if (entity is File && entity.path.endsWith('.json')) {
              final name = entity.uri.pathSegments.last;
              final lang = name.substring(0, name.length - 5);
              if (lang.isNotEmpty) {
                locales.add(lang);
              }
            }
          }
        }
      } catch (_) {}

      LuaValueCodec.push(ls, locales);
      return 1;
    });
    ls.setField(-2, 'allLocales');

    ls.setGlobal('i18n');
  }
}
