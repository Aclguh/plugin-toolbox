import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'plugin_package_inspection.dart';
import 'plugin_store_entry.dart';
import 'plugin_store_exception.dart';

export 'plugin_store_exception.dart';

/// 插件商店的下载源抽象。
///
/// 宿主只依赖本接口：生产环境注入 [JsDelivrPluginStoreSource]，
/// 测试与 `tool/verify.dart` 注入内存替身，两者共享同一套上层安装流程。
abstract class PluginStoreSource {
  /// 拉取远端插件目录（版本、简介、权限与 .ptx 下载地址）
  Future<PluginStoreCatalog> fetchCatalog();

  /// 下载指定条目的 .ptx 原始字节
  Future<Uint8List> downloadPackage(PluginStoreEntry entry);
}

/// 基于 jsDelivr 全球 CDN 的插件商店客户端。
///
/// 目录数据取自 jsDelivr 的仓库文件清单接口（一次请求返回整仓文件列表），
/// 再按需拉取 `plugin-source/<id>/plugin.json`；安装包取自 `dist/<id>.ptx`。
///
/// 为什么不用 GitHub Contents API：GitHub 对未认证请求限制 60 次/小时，
/// 而"列出目录 + 逐个读取清单 + 逐个下载"完成一次刷新就需要近百次请求，
/// 实测极易触发 403 限流；jsDelivr 的清单接口一次请求即可拿到全部 47 个
/// 插件的路径、体积与内容哈希，且无此类配额限制。
///
/// 缓存策略：清单接口返回的每个文件都带内容哈希，用它作为缓存键——
/// 插件源码未变化时刷新目录不再重复下载 plugin.json（同版本目录二次刷新
/// 只需 1 次请求），体积信息也直接来自清单，无需额外探测。
class JsDelivrPluginStoreSource implements PluginStoreSource {
  JsDelivrPluginStoreSource({
    required this.owner,
    required this.repository,
    this.ref = 'master',
    this.sourceDirectory = 'plugin-source',
    this.distDirectory = 'dist',
    this.maxPackageBytes = 10 * 1024 * 1024,
    this.maxConcurrentRequests = 8,
    this.requestTimeout = const Duration(seconds: 20),
    http.Client? httpClient,
    SharedPreferences? preferences,
  })  : _http = httpClient ?? http.Client(),
        _ownsHttpClient = httpClient == null,
        _preferences = preferences;

  /// 仓库所属用户/组织
  final String owner;

  /// 仓库名
  final String repository;

  /// 分支或标签；语义化版本标签（如 `v1.0.0`）可让目录与安装包稳定指向同一份提交
  final String ref;

  /// 插件源码目录名（版本与简介的权威来源）
  final String sourceDirectory;

  /// 插件产物目录名
  final String distDirectory;

  /// 安装包体积上限，与 PluginInstaller 保持一致（10MB）
  final int maxPackageBytes;

  /// 并发请求数上限：CDN 对突发请求同样会有节流，逐个串行又太慢
  final int maxConcurrentRequests;

  final Duration requestTimeout;

  final http.Client _http;
  final bool _ownsHttpClient;
  final SharedPreferences? _preferences;

  /// 进程内清单缓存（内容哈希 -> 清单），避免同一次会话内重复拉取
  final Map<String, Map<String, dynamic>> _manifestCache = {};

  static const String _dataApiBase = 'https://data.jsdelivr.com/v1';
  static const String _cdnBase = 'https://cdn.jsdelivr.net/gh';

  /// 仓库主页地址（界面展示用）
  String get repositoryUrl => 'https://github.com/$owner/$repository';

  /// 释放内部持有的 HTTP 连接
  void close() {
    if (_ownsHttpClient) _http.close();
  }

  @override
  Future<PluginStoreCatalog> fetchCatalog() async {
    await _loadCache();

    final listing = await _getJson(
      Uri.parse('$_dataApiBase/package/gh/$owner/$repository@$ref/flat'),
      notFoundMessage: '未找到仓库 $owner/$repository 的 $ref 分支',
    );

    final files = listing['files'];
    if (files is! List) {
      throw const PluginStoreException('插件目录清单格式异常');
    }

    // 从整仓文件清单中挑出插件清单与安装包, 按插件 id 归并
    final manifestHashes = <String, _FlatFile>{};
    final packages = <String, _FlatFile>{};
    for (final raw in files) {
      if (raw is! Map) continue;
      final file = _FlatFile.fromJson(Map<String, dynamic>.from(raw));
      if (file == null) continue;

      final manifestId = _matchUnder(sourceDirectory, 'plugin.json', file.name);
      if (manifestId != null) {
        manifestHashes[manifestId] = file;
        continue;
      }
      final packageId = _matchPackage(file.name);
      if (packageId != null) packages[packageId] = file;
    }

    final skipped = <String>[];
    final entries = <PluginStoreEntry>[];
    final resolvedHashes = <String, String>{};

    await _forEachConcurrent(manifestHashes.entries.toList(), (pair) async {
      final id = pair.key;
      final manifestFile = pair.value;
      try {
        final manifest = await _loadManifest(id, manifestFile);
        resolvedHashes[id] = manifestFile.hash;
        entries.add(_buildEntry(
          id: id,
          manifest: manifest,
          manifestFile: manifestFile,
          packageFile: packages[id],
        ));
      } on PluginStoreException catch (e) {
        skipped.add('$id: ${e.message}');
      } catch (e) {
        skipped.add('$id: $e');
      }
    });

    entries.sort((a, b) => a.id.compareTo(b.id));
    skipped.sort();
    await _storeCache(manifestHashes.values.map((f) => f.hash).toSet());

    return PluginStoreCatalog(
      entries: List.unmodifiable(entries),
      revision: ref,
      fetchedAt: DateTime.now(),
      skipped: List.unmodifiable(skipped),
    );
  }

  @override
  Future<Uint8List> downloadPackage(PluginStoreEntry entry) async {
    if (entry.packageUrl == null) {
      throw PluginStoreException('远端缺少安装包 ${entry.id}.ptx');
    }
    final response = await _get(Uri.parse(entry.packageUrl!));
    if (response.statusCode == 404) {
      throw PluginStoreNotFoundException('远端缺少安装包 ${entry.id}.ptx');
    }
    if (response.statusCode != 200) {
      throw PluginStoreException('下载安装包失败 (HTTP ${response.statusCode})');
    }

    final bytes = response.bodyBytes;
    if (bytes.isEmpty) {
      throw PluginStoreException('远端安装包 ${entry.id}.ptx 内容为空');
    }
    if (bytes.length > maxPackageBytes) {
      throw PluginStoreException(
        '安装包过大 ($bytes 字节，上限 ${maxPackageBytes ~/ (1024 * 1024)}MB)',
      );
    }
    return bytes;
  }

  /// 读取安装包内容中的清单与顶层条目名。
  ///
  /// 用于安装前把"商店展示的元数据"与"实际产物的清单"对齐：
  /// 目录来自 `plugin-source`，安装包来自 `dist`，两者由不同提交产出时
  /// 可能出现 id / 入口脚本不一致，此处提前发现并给出提示。
  static PluginPackageContract inspectPackage(Uint8List bytes) =>
      inspectPluginPackage(bytes);

  /// 按内容哈希加载插件清单。
  ///
  /// 缓存的是"原始清单正文 + 校验结果"而非校验后的对象：仓库里可能存在
  /// id 与目录名不一致的脏清单，若只缓存合法清单，每次刷新都会为同一个
  /// 脏文件重复请求——缓存必须同时覆盖合法与非法条目才能真正省下请求。
  Future<Map<String, dynamic>> _loadManifest(String id, _FlatFile file) async {
    final cached = _manifestCache[file.hash];
    if (cached != null) return _validateManifest(cached, id: id);

    final body = await _getJson(
      Uri.parse('$_cdnBase/$owner/$repository@$ref/${file.cdnPath}'),
      notFoundMessage: '缺少 $sourceDirectory/$id/plugin.json',
    );
    _manifestCache[file.hash] = body;
    return _validateManifest(body, id: id);
  }

  Map<String, dynamic> _validateManifest(Map<String, dynamic> manifest, {required String id}) {
    if ((manifest['id']?.toString() ?? '').isEmpty ||
        (manifest['name']?.toString() ?? '').isEmpty) {
      throw const PluginStoreException('plugin.json 缺少必填字段 id / name');
    }
    final manifestId = manifest['id'].toString();
    if (manifestId != id) {
      throw PluginStoreException('plugin.json 的 id ($manifestId) 与目录名不一致');
    }
    return manifest;
  }

  PluginStoreEntry _buildEntry({
    required String id,
    required Map<String, dynamic> manifest,
    required _FlatFile manifestFile,
    required _FlatFile? packageFile,
  }) {
    return PluginStoreEntry(
      id: id,
      name: manifest['name'].toString(),
      version: manifest['version']?.toString() ?? '0.0.0',
      description: manifest['description']?.toString() ?? '',
      author: manifest['author']?.toString() ?? 'Unknown',
      category: manifest['category']?.toString() ?? 'other',
      permissions: manifest['permissions'] is List
          ? (manifest['permissions'] as List).map((e) => e.toString()).toList()
          : const [],
      minAppVersion: manifest['minAppVersion']?.toString(),
      packageName: packageFile?.baseName,
      packageSizeBytes: packageFile?.size,
      packageApiUrl: packageFile == null
          ? null
          : '$_cdnBase/$owner/$repository@$ref/${packageFile.cdnPath}',
      packageUrl: packageFile == null
          ? null
          : '$_cdnBase/$owner/$repository@$ref/${packageFile.cdnPath}',
      manifestApiUrl: '$_cdnBase/$owner/$repository@$ref/${manifestFile.cdnPath}',
      sourcePath: '$sourceDirectory/$id',
    );
  }

  /// 匹配 `<dir>/<pluginId>/<fileName>` 形式的文件，返回插件 id
  String? _matchUnder(String directory, String fileName, String path) {
    final prefix = '/$directory/';
    final suffix = '/$fileName';
    if (!path.startsWith(prefix) || !path.endsWith(suffix)) return null;
    final id = path.substring(prefix.length, path.length - suffix.length);
    if (id.isEmpty || id.contains('/')) return null;
    return id;
  }

  String? _matchPackage(String path) {
    final prefix = '/$distDirectory/';
    if (!path.startsWith(prefix) || !path.endsWith('.ptx')) return null;
    final name = path.substring(prefix.length);
    if (name.isEmpty || name.contains('/')) return null;
    return name.substring(0, name.length - '.ptx'.length);
  }

  Future<void> _loadCache() async {
    final prefs = _preferences;
    if (prefs == null) return;
    try {
      final raw = prefs.getString(_cacheKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = json.decode(raw);
      if (decoded is! Map) return;
      final manifests = decoded['manifests'];
      if (manifests is! Map) return;
      for (final entry in manifests.entries) {
        final value = entry.value;
        if (value is Map) {
          _manifestCache[entry.key.toString()] =
              Map<String, dynamic>.from(value);
        }
      }
    } catch (_) {
      // 缓存损坏时静默降级为全量拉取, 绝不影响商店可用性
      _manifestCache.clear();
    }
  }

  Future<void> _storeCache(Set<String> activeHashes) async {
    final prefs = _preferences;
    if (prefs == null) return;
    try {
      // 只保留当前仓库清单中仍存在的哈希, 避免缓存随插件增删无限膨胀。
      // activeHashes 来自本次文件清单, 因此合法与非法条目都能被正确保留。
      final manifests = <String, dynamic>{};
      for (final entry in _manifestCache.entries) {
        if (activeHashes.contains(entry.key)) {
          manifests[entry.key] = entry.value;
        }
      }
      _manifestCache
        ..clear()
        ..addAll({
          for (final entry in manifests.entries)
            entry.key: Map<String, dynamic>.from(entry.value as Map),
        });
      await prefs.setString(_cacheKey, json.encode({'manifests': manifests}));
    } catch (_) {
      // 缓存写入失败只影响下次刷新的请求数, 不阻断流程
    }
  }

  String get _cacheKey => 'plugin_store_cache_${owner}_${repository}_$ref';

  Future<Map<String, dynamic>> _getJson(
    Uri uri, {
    required String notFoundMessage,
  }) async {
    final response = await _get(uri);
    if (response.statusCode == 404) {
      throw PluginStoreNotFoundException(notFoundMessage);
    }
    if (response.statusCode == 403 || response.statusCode == 429) {
      throw const PluginStoreException('插件商店请求过于频繁，请稍后重试');
    }
    if (response.statusCode != 200) {
      throw PluginStoreException('插件商店返回异常状态 (${response.statusCode})');
    }

    final Object? decoded;
    try {
      decoded = json.decode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw const PluginStoreException('插件商店返回了无法解析的数据');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const PluginStoreException('插件商店返回了非预期的 JSON 结构');
    }
    return decoded;
  }

  Future<http.Response> _get(Uri uri) async {
    try {
      return await _http.get(uri, headers: const {
        'Accept': 'application/json',
        'User-Agent': 'PluginToolbox-Store',
      }).timeout(requestTimeout);
    } on TimeoutException {
      throw const PluginStoreException('网络请求超时，请检查网络后重试');
    } on SocketException {
      throw const PluginStoreException('无法连接插件商店，请检查网络后重试');
    } on http.ClientException {
      throw const PluginStoreException('无法连接插件商店，请检查网络后重试');
    }
  }

  /// 以固定并发数遍历 [items]，单项异常由调用方在回调内自行处理。
  Future<void> _forEachConcurrent<T>(
    List<T> items,
    Future<void> Function(T item) worker,
  ) async {
    if (items.isEmpty) return;
    final concurrency = maxConcurrentRequests.clamp(1, items.length);
    int cursor = 0;
    await Future.wait(List.generate(concurrency, (_) async {
      while (true) {
        final index = cursor++;
        if (index >= items.length) return;
        await worker(items[index]);
      }
    }));
  }
}

/// jsDelivr 清单接口的单条文件记录
class _FlatFile {
  const _FlatFile({required this.name, required this.hash, required this.size});

  /// 仓库内绝对路径（形如 `/dist/base64_tool.ptx`）
  final String name;

  /// jsDelivr 给出的内容哈希（SHA-256 的 base64），跨启动缓存键
  final String hash;

  final int? size;

  /// 拼 CDN 地址用的相对路径（CDN 路径中不能出现连续斜杠）
  String get cdnPath => name.startsWith('/') ? name.substring(1) : name;

  /// 文件名（不含目录）
  String get baseName => name.split('/').last;

  static _FlatFile? fromJson(Map<String, dynamic> json) {
    final name = json['name'];
    final hash = json['hash'];
    if (name is! String || hash is! String || name.isEmpty) return null;
    final size = json['size'];
    return _FlatFile(
      name: name.startsWith('/') ? name : '/$name',
      hash: hash,
      size: size is num ? size.toInt() : null,
    );
  }
}
