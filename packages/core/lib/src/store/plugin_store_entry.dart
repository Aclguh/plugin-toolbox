/// 插件商店条目：聚合「远端插件源码清单（`plugin-source/<id>/plugin.json`）」
/// 与「远端可下载的 .ptx 产物」两项信息。
///
/// 版本号与简介一律取自 plugin-source 的 plugin.json（开发源是权威元数据），
/// 下载地址则指向 GitHub Contents API 给出的 .ptx 文件（见 [apiUrl]）。
class PluginStoreEntry {
  const PluginStoreEntry({
    required this.id,
    required this.name,
    required this.version,
    required this.description,
    required this.author,
    required this.category,
    required this.permissions,
    this.minAppVersion,
    this.packageName,
    this.packageSizeBytes,
    this.packageApiUrl,
    this.packageUrl,
    required this.manifestApiUrl,
    required this.sourcePath,
  });

  /// 插件唯一标识（与目录名、.ptx 文件名一致）
  final String id;

  /// 插件显示名
  final String name;

  /// 插件版本号（来自 plugin-source/plugin.json）
  final String version;

  /// 插件简介（来自 plugin-source/plugin.json）
  final String description;

  /// 插件作者
  final String author;

  /// 插件分类名（对应宿主 PluginCategory.name，未知分类由宿主降级为 other）
  final String category;

  /// 插件声明的权限名列表（仅用于安装前向用户展示）
  final List<String> permissions;

  /// 插件要求的最低宿主版本
  final String? minAppVersion;

  /// 远端 .ptx 文件名，如 `qr_tool.ptx`
  final String? packageName;

  /// 远端 .ptx 体积（字节，取自 GitHub contents 元数据）
  final int? packageSizeBytes;

  /// 远端 .ptx 的 Contents API 地址（携带 ref，锚定目录快照对应的提交）
  final String? packageApiUrl;

  /// 远端 .ptx 的公开下载直链（raw.githubusercontent.com，无法访问时仅作展示）
  final String? packageUrl;

  /// 远端 plugin.json 的 Contents API 地址
  final String manifestApiUrl;

  /// 远端源码仓库内的相对路径，如 `plugin-source/qr_tool`
  final String sourcePath;

  /// 安装包体积的可读文案
  String get packageSizeLabel {
    final bytes = packageSizeBytes;
    if (bytes == null) return '未知';
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    return '${(kb / 1024).toStringAsFixed(2)} MB';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'version': version,
        'description': description,
        'author': author,
        'category': category,
        'permissions': permissions,
        'minAppVersion': minAppVersion,
        'packageName': packageName,
        'packageSizeBytes': packageSizeBytes,
        'packageApiUrl': packageApiUrl,
        'packageUrl': packageUrl,
        'manifestApiUrl': manifestApiUrl,
        'sourcePath': sourcePath,
      };
}

/// 商店目录快照：一次成功的目录拉取结果。
///
/// [revision] 记录本次拉取锚定的提交/分支，用作下载地址的 ref，
/// 避免"列表来自旧快照、下载却拿到新产物"的不一致。
class PluginStoreCatalog {
  const PluginStoreCatalog({
    required this.entries,
    required this.revision,
    required this.fetchedAt,
    this.skipped = const [],
  });

  /// 成功解析的插件条目（按 id 升序）
  final List<PluginStoreEntry> entries;

  /// 本次快照锚定的 ref（GitHub contents 的 sha 或分支名）
  final String revision;

  /// 拉取时间
  final DateTime fetchedAt;

  /// 解析失败被跳过的插件目录与原因（远端脏数据不应阻断整个目录）
  final List<String> skipped;

  bool get isEmpty => entries.isEmpty;
}
