import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/app_providers.dart';
import '../storage/shared_preferences_store.dart';
import 'store_service.dart';

/// 插件商店的远端仓库坐标。
///
/// 默认指向官方插件开发仓库 Aclguh/PTX-plugins：`plugin-source/<id>/plugin.json`
/// 提供版本与简介元数据，`dist/<id>.ptx` 提供可安装产物。
const String kPluginStoreOwner = 'Aclguh';
const String kPluginStoreRepository = 'PTX-plugins';

/// 经过验证的内置基准提交快照（离线或限流时的可靠兜底快照）。
const String kPluginStoreFallbackRef =
    'd8e4e63b71a0a4fd4b4c7b001b735c3864e68734';

/// 保持向后兼容的引用常量（默认指向当前基准）。
const String kPluginStoreRef = kPluginStoreFallbackRef;

/// 动态解析或本地缓存的最新仓库 ref。
final pluginStoreResolvedRefProvider = FutureProvider<String>((ref) async {
  final prefs = ref.watch(sharedPreferencesProvider);
  final repoConfig = ref.watch(customPluginRepositoryProvider);
  return JsDelivrPluginStoreSource.resolveLatestRef(
    owner: repoConfig.owner,
    repository: repoConfig.repository,
    fallbackRef: repoConfig.isDefault ? kPluginStoreFallbackRef : 'HEAD',
    preferences: SharedPreferencesKeyValueStore(prefs),
  );
});

/// 自定义插件仓库配置 Notifier，负责持久化至 SharedPreferences。
class PluginRepositoryNotifier extends StateNotifier<PluginRepositoryConfig> {
  PluginRepositoryNotifier(this._prefs) : super(_load(_prefs)) {
    _loadSaved();
  }

  final SharedPreferences _prefs;
  static const customRepoKey = 'custom_plugin_store_repository';
  static const savedReposKey = 'saved_plugin_store_repositories';

  List<PluginRepositoryConfig> _savedConfigs = [
    PluginRepositoryConfig.defaultConfig
  ];

  /// 已保存的多仓库源列表（默认包含官方默认源）
  List<PluginRepositoryConfig> get savedConfigs =>
      List.unmodifiable(_savedConfigs);

  void _loadSaved() {
    final raw = safeRead(_prefs, savedReposKey, null, _prefs.getStringList);
    if (raw != null && raw.isNotEmpty) {
      final list = <PluginRepositoryConfig>[
        PluginRepositoryConfig.defaultConfig
      ];
      for (final s in raw) {
        final parsed = PluginRepositoryConfig.tryParse(s);
        if (parsed != null &&
            !list.any((e) =>
                e.owner.toLowerCase() == parsed.owner.toLowerCase() &&
                e.repository.toLowerCase() ==
                    parsed.repository.toLowerCase())) {
          list.add(parsed);
        }
      }
      _savedConfigs = list;
    }
  }

  Future<void> _persistSaved() async {
    try {
      final urls = _savedConfigs
          .where((e) => !e.isDefault)
          .map((e) => e.githubUrl)
          .toList();
      await _prefs.setStringList(savedReposKey, urls);
    } catch (_) {}
  }

  static PluginRepositoryConfig _load(SharedPreferences prefs) {
    final saved = safeRead(prefs, customRepoKey, null, prefs.getString);
    if (saved != null && saved.trim().isNotEmpty) {
      final parsed = PluginRepositoryConfig.tryParse(saved);
      if (parsed != null) return parsed;
    }
    return PluginRepositoryConfig.defaultConfig;
  }

  /// 设置并激活新的插件仓库，同时将其记录入已保存列表
  Future<bool> setRepository(String input) async {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      await resetToDefault();
      return true;
    }
    final parsed = PluginRepositoryConfig.tryParse(trimmed);
    if (parsed == null) return false;

    state = parsed;
    if (!_savedConfigs.any((e) =>
        e.owner.toLowerCase() == parsed.owner.toLowerCase() &&
        e.repository.toLowerCase() == parsed.repository.toLowerCase())) {
      _savedConfigs.add(parsed);
      await _persistSaved();
    }

    try {
      if (parsed.isDefault) {
        await _prefs.remove(customRepoKey);
      } else {
        await _prefs.setString(customRepoKey, parsed.githubUrl);
      }
    } catch (_) {}
    return true;
  }

  /// 从列表中移除某个已保存的非默认源
  Future<void> removeSavedRepository(PluginRepositoryConfig config) async {
    if (config.isDefault) return;
    _savedConfigs.removeWhere((e) =>
        e.owner.toLowerCase() == config.owner.toLowerCase() &&
        e.repository.toLowerCase() == config.repository.toLowerCase());
    await _persistSaved();

    if (state.owner.toLowerCase() == config.owner.toLowerCase() &&
        state.repository.toLowerCase() == config.repository.toLowerCase()) {
      await resetToDefault();
    }
  }

  /// 恢复为官方默认插件仓库
  Future<void> resetToDefault() async {
    state = PluginRepositoryConfig.defaultConfig;
    try {
      await _prefs.remove(customRepoKey);
    } catch (_) {}
  }
}

/// 自定义插件仓库配置 Provider
final customPluginRepositoryProvider =
    StateNotifierProvider<PluginRepositoryNotifier, PluginRepositoryConfig>(
        (ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return PluginRepositoryNotifier(prefs);
});

/// 商店页依赖的服务。测试通过 override 注入内存替身，避免真实网络请求。
final pluginStoreServiceProvider = Provider<PluginStoreService>((ref) {
  final repoConfig = ref.watch(customPluginRepositoryProvider);
  final fallbackRef = repoConfig.isDefault ? kPluginStoreFallbackRef : 'HEAD';
  final resolvedRef =
      ref.watch(pluginStoreResolvedRefProvider).valueOrNull ?? fallbackRef;
  final client = JsDelivrPluginStoreSource(
    owner: repoConfig.owner,
    repository: repoConfig.repository,
    ref: resolvedRef,
    // 借用已注入的 SharedPreferences 缓存清单：源码未变化的插件刷新时
    // 不再重复下载 plugin.json，把一次刷新的请求数压到接近 1 次
    preferences:
        SharedPreferencesKeyValueStore(ref.watch(sharedPreferencesProvider)),
  );
  ref.onDispose(client.close);
  return PluginStoreService(source: client);
});

/// 商店目录拉取结果。以 FutureProvider 承载，便于下拉/按钮刷新时 invalidate 重取。
final pluginStoreCatalogProvider =
    FutureProvider<PluginStoreCatalog>((ref) async {
  final service = ref.watch(pluginStoreServiceProvider);
  return service.fetchCatalog();
});
