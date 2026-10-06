import 'dart:convert';
import 'plugin_category.dart';
import 'plugin_permission.dart';

/// 对应 plugin.json 清单文件
class PluginManifest {
  final String id;
  final String name;
  final String version;
  final String description;
  final String author;
  final String? minAppVersion;
  final String type; // 'lua' | 'webview'
  final PluginCategory category;
  final String? icon;
  final List<PluginPermission> permissions;
  final String entry; // e.g. "main.lua"
  final String ui;    // e.g. "ui/main.ui.json"
  final List<Map<String, dynamic>> settings;
  final int storageQuotaMb;

  const PluginManifest({
    required this.id,
    required this.name,
    required this.version,
    required this.description,
    required this.author,
    this.minAppVersion,
    required this.type,
    required this.category,
    this.icon,
    required this.permissions,
    required this.entry,
    required this.ui,
    this.settings = const [],
    this.storageQuotaMb = 50,
  });

  /// 安全解析清单。
  ///
  /// 恶意或损坏的 plugin.json 不允许引发 TypeError 崩溃：可降级字段统一走
  /// 容错转换，必填字段（id/name）缺失或类型错误时抛出明确的 FormatException。
  factory PluginManifest.fromJson(Map<String, dynamic> json) {
    String requiredField(String key) {
      final value = json[key];
      if (value == null || value.toString().isEmpty) {
        throw FormatException('插件清单缺少必填字段: $key');
      }
      return value.toString();
    }

    final permissionsRaw = json['permissions'] is List
        ? json['permissions'] as List<dynamic>
        : const <dynamic>[];
    final settingsRaw = json['settings'] is List
        ? json['settings'] as List<dynamic>
        : const <dynamic>[];
    final permissions = permissionsRaw
        .map((p) => PluginPermission.fromString(p.toString()))
        .whereType<PluginPermission>()
        .toList();

    return PluginManifest(
      id: requiredField('id'),
      name: requiredField('name'),
      version: json['version']?.toString() ?? '1.0.0',
      description: json['description']?.toString() ?? '',
      author: json['author']?.toString() ?? 'Unknown',
      minAppVersion: json['minAppVersion']?.toString(),
      type: (json['type']?.toString() ?? 'lua').toLowerCase(),
      category: PluginCategory.fromString(json['category']?.toString()),
      icon: json['icon']?.toString(),
      permissions: permissions,
      entry: json['entry']?.toString() ?? 'main.lua',
      ui: json['ui']?.toString() ?? 'ui/main.ui.json',
      settings: settingsRaw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(),
      storageQuotaMb: (json['storageQuotaMb'] is num)
          ? (json['storageQuotaMb'] as num).toInt()
          : 50,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'version': version,
        'description': description,
        'author': author,
        'minAppVersion': minAppVersion,
        'type': type,
        'category': category.name,
        'icon': icon,
        'permissions': permissions.map((p) => p.name).toList(),
        'entry': entry,
        'ui': ui,
        'settings': settings,
        'storageQuotaMb': storageQuotaMb,
      };

  static PluginManifest fromJsonString(String source) {
    final Object? decoded;
    try {
      decoded = json.decode(source);
    } on FormatException {
      rethrow;
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('插件清单必须是 JSON 对象');
    }
    return PluginManifest.fromJson(decoded);
  }
}
