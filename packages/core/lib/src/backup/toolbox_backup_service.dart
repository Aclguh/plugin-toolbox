import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import '../storage/key_value_store.dart';
import '../model/plugin_manifest.dart';
import '../model/plugin_permission.dart';
import '../plugin/dynamic_plugin.dart';
import '../plugin/plugin_registry.dart';
import '../sandbox/sandbox_path.dart';

/// 工具箱备份清单元数据模型
class ToolboxBackupManifest {
  final int version;
  final String timestamp;
  final String? appVersion;
  final List<String> pluginOrder;
  final List<String> disabledPluginIds;
  final Map<String, List<String>> customPermissions;
  final Map<String, dynamic> preferences;
  final List<String> pluginIds;

  const ToolboxBackupManifest({
    this.version = 1,
    required this.timestamp,
    this.appVersion,
    this.pluginOrder = const [],
    this.disabledPluginIds = const [],
    this.customPermissions = const {},
    this.preferences = const {},
    this.pluginIds = const [],
  });

  Map<String, dynamic> toJson() => {
        'version': version,
        'timestamp': timestamp,
        if (appVersion != null) 'appVersion': appVersion,
        'pluginOrder': pluginOrder,
        'disabledPluginIds': disabledPluginIds,
        'customPermissions': customPermissions,
        'preferences': preferences,
        'pluginIds': pluginIds,
      };

  factory ToolboxBackupManifest.fromJson(Map<String, dynamic> json) {
    return ToolboxBackupManifest(
      version: json['version'] as int? ?? 1,
      timestamp: json['timestamp'] as String? ?? '',
      appVersion: json['appVersion'] as String?,
      pluginOrder: (json['pluginOrder'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      disabledPluginIds: (json['disabledPluginIds'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      customPermissions: (json['customPermissions'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(
                    k,
                    (v as List<dynamic>).map((e) => e.toString()).toList(),
                  )) ??
          const {},
      preferences: (json['preferences'] as Map<String, dynamic>?) ?? const {},
      pluginIds: (json['pluginIds'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory ToolboxBackupManifest.fromJsonString(String source) =>
      ToolboxBackupManifest.fromJson(
          jsonDecode(source) as Map<String, dynamic>);
}

/// 还原执行结果与指标统计
class ToolboxBackupResult {
  final bool success;
  final ToolboxBackupManifest manifest;
  final List<String> restoredPlugins;
  final List<String> failedPlugins;
  final String? error;

  const ToolboxBackupResult({
    required this.success,
    required this.manifest,
    this.restoredPlugins = const [],
    this.failedPlugins = const [],
    this.error,
  });
}

/// 工具箱全量插件、配置与沙箱存储数据的统一打包备份与还原服务
class ToolboxBackupService {
  ToolboxBackupService._();

  static const String manifestFileName = 'backup_manifest.json';
  static const int maxBackupFileSizeBytes = 50 * 1024 * 1024; // 50MB
  static const int maxUncompressedSizeBytes = 100 * 1024 * 1024; // 100MB
  static const int maxEntryCount = 2000;

  /// 创建全量备份并返回 ZIP 压缩归档字节数组
  static Future<List<int>> createBackupBytes({
    required Directory pluginsDirectory,
    List<String>? pluginOrder,
    Iterable<String>? disabledPluginIds,
    Map<String, Set<PluginPermission>>? customPermissions,
    Map<String, dynamic>? preferences,
    String? appVersion,
    bool includeStorage = true,
  }) async {
    final archive = Archive();
    final pluginIds = <String>[];

    if (pluginsDirectory.existsSync()) {
      final entities = pluginsDirectory.listSync();
      for (final entity in entities) {
        if (entity is Directory) {
          final pluginId = entity.path.replaceAll('\\', '/').split('/').last;
          if (pluginId.startsWith('.')) continue; // 跳过临时 staging/backup 目录

          final manifestFile = File('${entity.path}/plugin.json');
          if (!manifestFile.existsSync()) continue;

          pluginIds.add(pluginId);

          // 收集插件目录下的所有文件
          final files = entity.listSync(recursive: true);
          for (final f in files) {
            if (f is File) {
              final relPath = f.path
                  .substring(entity.path.length + 1)
                  .replaceAll('\\', '/');

              // 安全与冗余过滤：跳过临时备份或隐藏文件
              if (relPath.startsWith('.') ||
                  relPath.endsWith('.backup') ||
                  relPath.endsWith('.staging')) {
                continue;
              }

              // 若不包含运行期存储，则排除 storage.json 与持久化存储文件
              if (!includeStorage &&
                  (relPath == 'storage.json' || relPath.startsWith('data/'))) {
                continue;
              }

              final bytes = await f.readAsBytes();
              archive.addFile(ArchiveFile(
                  'plugins/$pluginId/$relPath', bytes.length, bytes));
            }
          }
        }
      }
    }

    final formattedPermissions = <String, List<String>>{};
    if (customPermissions != null) {
      for (final entry in customPermissions.entries) {
        formattedPermissions[entry.key] =
            entry.value.map((p) => p.name).toList();
      }
    }

    final manifest = ToolboxBackupManifest(
      version: 1,
      timestamp: DateTime.now().toUtc().toIso8601String(),
      appVersion: appVersion,
      pluginOrder: pluginOrder ?? pluginIds,
      disabledPluginIds: disabledPluginIds?.toList() ?? const [],
      customPermissions: formattedPermissions,
      preferences: preferences ?? const {},
      pluginIds: pluginIds,
    );

    final manifestBytes = utf8.encode(manifest.toJsonString());
    archive.addFile(
        ArchiveFile(manifestFileName, manifestBytes.length, manifestBytes));

    final zipData = ZipEncoder().encode(archive);
    return zipData ?? <int>[];
  }

  /// 创建全量备份并保存到指定目标文件
  static Future<File> createBackupFile({
    required File targetFile,
    required Directory pluginsDirectory,
    List<String>? pluginOrder,
    Iterable<String>? disabledPluginIds,
    Map<String, Set<PluginPermission>>? customPermissions,
    Map<String, dynamic>? preferences,
    String? appVersion,
    bool includeStorage = true,
  }) async {
    final bytes = await createBackupBytes(
      pluginsDirectory: pluginsDirectory,
      pluginOrder: pluginOrder,
      disabledPluginIds: disabledPluginIds,
      customPermissions: customPermissions,
      preferences: preferences,
      appVersion: appVersion,
      includeStorage: includeStorage,
    );
    await targetFile.parent.create(recursive: true);
    return await targetFile.writeAsBytes(bytes, flush: true);
  }

  /// 检查并解析备份归档中的清单元数据（不解压实际插件文件）
  static Future<ToolboxBackupManifest> inspectBackup(List<int> zipBytes) async {
    if (zipBytes.length > maxBackupFileSizeBytes) {
      throw const FormatException('备份归档文件体积超限 (超过 50MB)');
    }
    final archive = ZipDecoder().decodeBytes(zipBytes);
    if (archive.files.length > maxEntryCount) {
      throw const FormatException('备份归档内条目数超限 (超过 2000 个)，疑似恶意压缩包');
    }

    final manifestEntry = archive.findFile(manifestFileName);
    if (manifestEntry == null) {
      throw const FormatException('备份归档中缺少 backup_manifest.json 描述文件');
    }

    final jsonStr = utf8.decode(manifestEntry.content as List<int>);
    return ToolboxBackupManifest.fromJsonString(jsonStr);
  }

  /// 从备份数据中还原插件与配置
  static Future<ToolboxBackupResult> restoreBackup({
    required List<int> zipBytes,
    required Directory pluginsDirectory,
    bool restoreStorage = true,
    bool overwrite = true,
    KeyValueStore? prefs,
    PluginRegistry? registry,
  }) async {
    if (zipBytes.length > maxBackupFileSizeBytes) {
      throw const FormatException('备份归档文件体积超限 (超过 50MB)');
    }

    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(zipBytes);
    } catch (_) {
      throw const FormatException('备份文件不是合法的 ZIP 归档格式');
    }

    if (archive.files.length > maxEntryCount) {
      throw const FormatException('备份归档内条目数超限 (超过 2000 个)，疑似恶意压缩包');
    }

    // 防 Zip Slip 路径穿越检验与总解压体积检验
    int totalBytes = 0;
    for (final file in archive.files) {
      if (!SandboxPath.isSafeRelativeEntry(file.name)) {
        throw FormatException('检测到非法的包内相对路径: ${file.name}');
      }
      totalBytes += file.size;
      if (totalBytes > maxUncompressedSizeBytes) {
        throw const FormatException('解压展开总体积超限 (超过 100MB)，疑似恶意解压炸弹');
      }
    }

    final manifestEntry = archive.findFile(manifestFileName);
    if (manifestEntry == null) {
      throw const FormatException('备份归档中缺少 backup_manifest.json 描述文件');
    }

    final manifest = ToolboxBackupManifest.fromJsonString(
        utf8.decode(manifestEntry.content as List<int>));

    // 使用临时暂存区以保证事务性
    final stagingDir =
        Directory('${pluginsDirectory.path}/.toolbox_restore_staging');
    if (stagingDir.existsSync()) {
      await stagingDir.delete(recursive: true);
    }
    await stagingDir.create(recursive: true);

    final restoredPlugins = <String>[];
    final failedPlugins = <String>[];

    try {
      // 提取文件至 staging 目录
      for (final file in archive.files) {
        if (file.name == manifestFileName) continue;
        if (!file.name.startsWith('plugins/')) continue;

        if (file.isFile) {
          final targetPath = '${stagingDir.path}/${file.name}';
          final outFile = File(targetPath);
          await outFile.parent.create(recursive: true);
          await outFile.writeAsBytes(file.content as List<int>, flush: true);
        }
      }

      // 将 staging 中的各插件移动到 pluginsDirectory 下
      final stagingPluginsDir = Directory('${stagingDir.path}/plugins');
      if (stagingPluginsDir.existsSync()) {
        final pluginEntities = stagingPluginsDir.listSync();
        for (final pEntity in pluginEntities) {
          if (pEntity is Directory) {
            final pluginId = pEntity.path.replaceAll('\\', '/').split('/').last;

            final targetPluginDir =
                Directory('${pluginsDirectory.path}/$pluginId');
            if (targetPluginDir.existsSync()) {
              if (overwrite) {
                await targetPluginDir.delete(recursive: true);
              } else {
                continue;
              }
            }

            await pEntity.rename(targetPluginDir.path);
            restoredPlugins.add(pluginId);
          }
        }
      }

      // 还原 SharedPreferences 配置（若提供）
      if (prefs != null) {
        if (manifest.pluginOrder.isNotEmpty) {
          await prefs.setStringList(
              'plugin_toolbox_plugin_order', manifest.pluginOrder);
        }
        if (manifest.disabledPluginIds.isNotEmpty) {
          await prefs.setStringList(
              'plugin_toolbox_disabled_plugins', manifest.disabledPluginIds);
        }
        for (final entry in manifest.customPermissions.entries) {
          await prefs.setStringList(
              'plugin_toolbox_permissions_${entry.key}', entry.value);
        }
        for (final prefEntry in manifest.preferences.entries) {
          final val = prefEntry.value;
          if (val is bool) {
            await prefs.setBool(prefEntry.key, val);
          } else if (val is int) {
            await prefs.setInt(prefEntry.key, val);
          } else if (val is double) {
            await prefs.setDouble(prefEntry.key, val);
          } else if (val is String) {
            await prefs.setString(prefEntry.key, val);
          } else if (val is List) {
            await prefs.setStringList(
                prefEntry.key, val.map((e) => e.toString()).toList());
          }
        }
      }

      // 同步内存中的 PluginRegistry（若提供）
      if (registry != null) {
        for (final pluginId in restoredPlugins) {
          final pluginManifestFile =
              File('${pluginsDirectory.path}/$pluginId/plugin.json');
          if (pluginManifestFile.existsSync()) {
            try {
              final mJson = await pluginManifestFile.readAsString();
              final pManifest = PluginManifest.fromJsonString(mJson);
              registry.register(DynamicPlugin(
                manifest: pManifest,
                rootDir: Directory('${pluginsDirectory.path}/$pluginId'),
              ));
            } catch (_) {}
          }
        }
        if (manifest.pluginOrder.isNotEmpty) {
          registry.loadOrder(manifest.pluginOrder);
        }
        if (manifest.disabledPluginIds.isNotEmpty) {
          registry.loadDisabledPlugins(manifest.disabledPluginIds);
        }
        if (manifest.customPermissions.isNotEmpty) {
          final permsMap = <String, Set<PluginPermission>>{};
          for (final entry in manifest.customPermissions.entries) {
            permsMap[entry.key] = entry.value
                .map((name) => PluginPermission.fromString(name))
                .whereType<PluginPermission>()
                .toSet();
          }
          registry.loadCustomPermissions(permsMap);
        }
      }

      return ToolboxBackupResult(
        success: true,
        manifest: manifest,
        restoredPlugins: restoredPlugins,
        failedPlugins: failedPlugins,
      );
    } catch (e) {
      return ToolboxBackupResult(
        success: false,
        manifest: manifest,
        restoredPlugins: restoredPlugins,
        failedPlugins: failedPlugins,
        error: e.toString(),
      );
    } finally {
      if (stagingDir.existsSync()) {
        try {
          await stagingDir.delete(recursive: true);
        } catch (_) {}
      }
    }
  }
}
