import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';

import '../providers/app_providers.dart';
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
  return JsDelivrPluginStoreSource.resolveLatestRef(
    owner: kPluginStoreOwner,
    repository: kPluginStoreRepository,
    fallbackRef: kPluginStoreFallbackRef,
    preferences: prefs,
  );
});

/// 商店页依赖的服务。测试通过 override 注入内存替身，避免真实网络请求。
final pluginStoreServiceProvider = Provider<PluginStoreService>((ref) {
  final resolvedRef = ref.watch(pluginStoreResolvedRefProvider).valueOrNull ??
      kPluginStoreFallbackRef;
  final client = JsDelivrPluginStoreSource(
    owner: kPluginStoreOwner,
    repository: kPluginStoreRepository,
    ref: resolvedRef,
    // 借用已注入的 SharedPreferences 缓存清单：源码未变化的插件刷新时
    // 不再重复下载 plugin.json，把一次刷新的请求数压到接近 1 次
    preferences: ref.watch(sharedPreferencesProvider),
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
