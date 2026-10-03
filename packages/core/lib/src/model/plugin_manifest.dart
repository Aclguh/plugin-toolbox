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
  });

  factory PluginManifest.fromJson(Map<String, dynamic> json) {
    final permissionsRaw = json['permissions'] as List<dynamic>? ?? [];
    final permissions = permissionsRaw
        .map((p) => PluginPermission.fromString(p.toString()))
        .whereType<PluginPermission>()
        .toList();

    return PluginManifest(
      id: json['id'] as String,
      name: json['name'] as String,
      version: json['version'] as String? ?? '1.0.0',
      description: json['description'] as String? ?? '',
      author: json['author'] as String? ?? 'Unknown',
      minAppVersion: json['minAppVersion'] as String?,
      type: (json['type'] as String? ?? 'lua').toLowerCase(),
      category: PluginCategory.fromString(json['category'] as String?),
      icon: json['icon'] as String?,
      permissions: permissions,
      entry: json['entry'] as String? ?? 'main.lua',
      ui: json['ui'] as String? ?? 'ui/main.ui.json',
      settings: (json['settings'] as List<dynamic>?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          const [],
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
      };

  static PluginManifest fromJsonString(String source) =>
      PluginManifest.fromJson(json.decode(source) as Map<String, dynamic>);
}
