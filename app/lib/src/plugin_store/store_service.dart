import 'dart:io';

import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';

/// 商店条目在界面上的完整呈现数据：远端元数据 + 本地安装态。
class PluginStoreItem {
  const PluginStoreItem({
    required this.entry,
    required this.state,
    required this.minAppVersionSatisfied,
    this.installedVersion,
  });

  /// 远端条目（版本、简介、作者、权限、安装包体积等均来自 plugin-source）
  final PluginStoreEntry entry;

  /// 本地安装态：未安装 / 可更新 / 已是最新
  final PluginStoreInstallState state;

  /// 宿主版本是否满足插件声明的最低版本要求
  final bool minAppVersionSatisfied;

  /// 本地已安装的版本号（未安装时为 null）
  final String? installedVersion;

  String get id => entry.id;
  String get name => entry.name;
  String get version => entry.version;
  String get description => entry.description;
}

/// 一次"下载并安装"的结果。
class StoreInstallOutcome {
  const StoreInstallOutcome({
    required this.plugin,
    required this.remoteVersion,
    this.warnings = const [],
  });

  /// 安装并落盘后的插件实例（尚未注册进注册中心）
  final DynamicPlugin plugin;

  /// 商店条目声明的版本号
  final String remoteVersion;

  /// 非阻断性提示（如安装包内版本与商店清单不一致）
  final List<String> warnings;

  bool get versionMatched => plugin.version == remoteVersion;
}

/// 插件商店的宿主侧服务：目录拉取、安装包下载落盘与安装，以及本地安装态比对。
///
/// 依赖全部由构造注入（[source] 与 [installer]），因此状态推导与安装编排可以在
/// 不触网、不落盘的前提下被单元测试覆盖；真实网络与解压安装由生产装配提供。
class PluginStoreService {
  PluginStoreService({
    required PluginStoreSource source,
    Future<DynamicPlugin> Function(File file)? installer,
    Future<Directory> Function()? temporaryDirectoryProvider,
  })  : _source = source,
        _installer = installer ?? PluginInstaller.installFromPtx,
        _temporaryDirectoryProvider =
            temporaryDirectoryProvider ?? _defaultTemporaryDirectory;

  final PluginStoreSource _source;
  final Future<DynamicPlugin> Function(File file) _installer;
  final Future<Directory> Function() _temporaryDirectoryProvider;

  /// 远端插件目录（按 id 升序）
  Future<PluginStoreCatalog> fetchCatalog() => _source.fetchCatalog();

  /// 结合本地已安装插件，推导每个条目的安装态。
  ///
  /// 宿主版本 [appVersion] 用于校验插件声明的 `minAppVersion`，
  /// [installedPlugins] 通常是注册中心当前的全部插件。
  List<PluginStoreItem> buildItems({
    required PluginStoreCatalog catalog,
    required List<ToolPlugin> installedPlugins,
    required String appVersion,
  }) {
    // ToolPlugin 基类不暴露清单对象，这里只取安装态判定需要的四个字段，
    // 避免把"插件是不是动态插件"的判断泄漏到商店逻辑里
    final installedManifests = installedPlugins.map(_manifestOf).toList();
    final versionById = {
      for (final plugin in installedPlugins) plugin.id: plugin.version,
    };

    return List.unmodifiable(catalog.entries.map((entry) {
      return PluginStoreItem(
        entry: entry,
        state: PluginStoreSemantics.resolveState(
          pluginId: entry.id,
          storeVersion: entry.version,
          installedManifests: installedManifests,
        ),
        minAppVersionSatisfied: PluginStoreSemantics.meetsMinAppVersion(
          appVersion,
          entry.minAppVersion,
        ),
        installedVersion: versionById[entry.id],
      );
    }));
  }

  PluginManifest _manifestOf(ToolPlugin plugin) => PluginManifest(
        id: plugin.id,
        name: plugin.name,
        version: plugin.version,
        description: plugin.description,
        author: '',
        type: 'lua',
        category: plugin.category,
        permissions: const [],
        entry: '',
        ui: '',
      );

  /// 下载并安装一个商店条目，返回安装结果。
  ///
  /// 全程不修改注册中心：注册与初始化由调用方在用户确认安装后统一执行，
  /// 保证"安装成功但注册失败"这类半成品状态不会出现。
  ///
  /// 落盘刻意使用同步文件 API：安装包上限 10MB（见 [PluginInstaller.maxPackageSizeBytes]），
  /// 单次写入是毫秒级操作，却让本方法在 fake-async 测试环境中保持完全确定性——
  /// 异步文件写入的后续微任务会被测试 zone 吞掉，导致安装流程永久悬挂。
  Future<StoreInstallOutcome> install(PluginStoreEntry entry) async {
    final bytes = await _source.downloadPackage(entry);

    // 安装前把"商店展示的元数据"与"实际产物的清单"对齐：
    // 目录来自 plugin-source、安装包来自 dist, 两者由不同提交产出时可能不一致
    final contract = inspectPluginPackage(bytes);

    final directory = await _temporaryDirectoryProvider();
    final file = File('${directory.path}/${entry.id}.ptx');
    try {
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes, flush: true);
      final plugin = await _installer(file);
      return StoreInstallOutcome(
        plugin: plugin,
        remoteVersion: entry.version,
        warnings: _buildWarnings(entry, plugin, contract),
      );
    } finally {
      // 临时安装包必须无条件清理：安装失败也不能在设备上留下残留产物
      try {
        if (file.existsSync()) file.deleteSync();
      } on FileSystemException {
        // 清理失败不影响安装结果
      }
    }
  }

  List<String> _buildWarnings(
    PluginStoreEntry entry,
    DynamicPlugin plugin,
    PluginPackageContract contract,
  ) {
    final warnings = <String>[];
    if (plugin.id != entry.id) {
      warnings.add('安装包内的插件 ID 为 ${plugin.id}，与商店条目 ${entry.id} 不一致');
    }
    if (PluginStoreSemantics.isUpdateAvailable(entry.version, plugin.version)) {
      warnings.add('安装包内版本 (${plugin.version}) 低于商店清单版本 (${entry.version})');
    }
    if (contract.missingEntryScript) {
      warnings.add('安装包内缺少入口脚本 ${contract.manifest.entry}');
    }
    if (contract.missingUiDefinition) {
      warnings.add('安装包内缺少 UI 描述 ${contract.manifest.ui}');
    }
    return warnings;
  }
}

Future<Directory> _defaultTemporaryDirectory() async {
  // 下载中转目录使用系统临时目录: 安装包安装后立即删除, 不占用插件沙箱配额
  return Directory.systemTemp.createTemp('ptx_store_');
}
