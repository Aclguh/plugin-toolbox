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

/// 目录锚定的分支、标签或提交哈希；发布插件时改用语义化版本标签或具体 commit SHA 可让目录与产物稳定同源。
///
/// 注意：jsDelivr Data API (`data.jsdelivr.com`) 对分支名称（如 `master`）具有长达 1 年的强缓存
/// (max-age=31536000)，且其 Purge 机制仅针对静态文件 CDN (`cdn.jsdelivr.net`)，无法清理 API 清单缓存。
/// 若锚定为 `master`，将持续返回首次建立缓存时的 47 个插件历史快照；
/// 锚定为最新发布的提交哈希 (commit SHA) 或 release tag 可彻底绕开陈旧缓存，实时获取仓库全部 130 款生态插件。
const String kPluginStoreRef = 'd8e4e63b71a0a4fd4b4c7b001b735c3864e68734';

/// 商店页依赖的服务。测试通过 override 注入内存替身，避免真实网络请求。
final pluginStoreServiceProvider = Provider<PluginStoreService>((ref) {
  final client = JsDelivrPluginStoreSource(
    owner: kPluginStoreOwner,
    repository: kPluginStoreRepository,
    ref: kPluginStoreRef,
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
