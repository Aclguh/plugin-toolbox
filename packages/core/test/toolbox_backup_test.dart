import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:test/test.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';
// 使用 MemoryKeyValueStore 替身

void main() {
  // 纯 Dart 单元测试环境初始化

  late Directory tempDir;
  late Directory pluginsDir;

  setUp(() async {
    // 消除 mock 残留
    tempDir = await Directory.systemTemp.createTemp('toolbox_backup_test_');
    pluginsDir = Directory('${tempDir.path}/plugins');
    await pluginsDir.create(recursive: true);
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('ToolboxBackupService Tests', () {
    test('ToolboxBackupManifest 序列化与反序列化双向一致性', () {
      const manifest = ToolboxBackupManifest(
        version: 1,
        timestamp: '2026-10-18T12:00:00Z',
        appVersion: '1.0.0',
        pluginOrder: ['plugin_a', 'plugin_b'],
        disabledPluginIds: ['plugin_b'],
        customPermissions: {
          'plugin_a': ['clipboard', 'network'],
        },
        preferences: {
          'theme': 'dark',
          'auto_rotate': true,
        },
        pluginIds: ['plugin_a', 'plugin_b'],
      );

      final jsonStr = manifest.toJsonString();
      final decoded = ToolboxBackupManifest.fromJsonString(jsonStr);

      expect(decoded.version, 1);
      expect(decoded.timestamp, '2026-10-18T12:00:00Z');
      expect(decoded.appVersion, '1.0.0');
      expect(decoded.pluginOrder, ['plugin_a', 'plugin_b']);
      expect(decoded.disabledPluginIds, ['plugin_b']);
      expect(decoded.customPermissions['plugin_a'], ['clipboard', 'network']);
      expect(decoded.preferences['theme'], 'dark');
      expect(decoded.preferences['auto_rotate'], isTrue);
      expect(decoded.pluginIds, ['plugin_a', 'plugin_b']);
    });

    test('全量备份打包 createBackupBytes 生成合法归档且 inspectBackup 可正常解析', () async {
      // 准备一个模拟插件目录
      final pluginADir = Directory('${pluginsDir.path}/demo_plugin');
      await pluginADir.create(recursive: true);
      await File('${pluginADir.path}/plugin.json').writeAsString(
        jsonEncode({
          'id': 'demo_plugin',
          'name': 'Demo Plugin',
          'version': '1.0.0',
          'entry': 'main.lua',
          'ui': 'ui/main.ui.json',
        }),
      );
      await File('${pluginADir.path}/main.lua').writeAsString('print("demo")');
      await File('${pluginADir.path}/storage.json')
          .writeAsString('{"key": "value"}');

      final zipBytes = await ToolboxBackupService.createBackupBytes(
        pluginsDirectory: pluginsDir,
        pluginOrder: ['demo_plugin'],
        disabledPluginIds: [],
        preferences: {'demo_pref': '123'},
        appVersion: '0.1.0',
        includeStorage: true,
      );

      expect(zipBytes, isNotEmpty);

      final inspected = await ToolboxBackupService.inspectBackup(zipBytes);
      expect(inspected.pluginIds, ['demo_plugin']);
      expect(inspected.pluginOrder, ['demo_plugin']);
      expect(inspected.preferences['demo_pref'], '123');
      expect(inspected.appVersion, '0.1.0');
    });

    test('restoreBackup 成功还原插件、持久化数据与 SharedPreferences 偏好及注册中心', () async {
      // 创建包含 demo_tool 插件的备份
      final originalPluginDir = Directory('${pluginsDir.path}/demo_tool');
      await originalPluginDir.create(recursive: true);
      await File('${originalPluginDir.path}/plugin.json').writeAsString(
        jsonEncode({
          'id': 'demo_tool',
          'name': 'Demo Tool',
          'version': '2.0.0',
          'entry': 'main.lua',
          'ui': 'ui/main.ui.json',
        }),
      );
      await File('${originalPluginDir.path}/main.lua')
          .writeAsString('return 42');
      await File('${originalPluginDir.path}/storage.json')
          .writeAsString('{"counter": 100}');

      final zipBytes = await ToolboxBackupService.createBackupBytes(
        pluginsDirectory: pluginsDir,
        pluginOrder: ['demo_tool'],
        disabledPluginIds: ['demo_tool'],
        customPermissions: {
          'demo_tool': {PluginPermission.clipboard},
        },
        preferences: {'custom_setting': 'hello'},
      );

      // 清理原始目录，准备目标还原目录
      await originalPluginDir.delete(recursive: true);
      expect(originalPluginDir.existsSync(), isFalse);

      final prefs = MemoryKeyValueStore();
      final registry = PluginRegistry(
        eventBus: EventBusImpl(),
        storageFactory: const PluginStorageFactory(),
      );

      final result = await ToolboxBackupService.restoreBackup(
        zipBytes: zipBytes,
        pluginsDirectory: pluginsDir,
        prefs: prefs,
        registry: registry,
      );

      expect(result.success, isTrue);
      expect(result.restoredPlugins, contains('demo_tool'));

      // 验证插件与文件落盘
      expect(File('${pluginsDir.path}/demo_tool/plugin.json').existsSync(),
          isTrue);
      expect(
          File('${pluginsDir.path}/demo_tool/main.lua').existsSync(), isTrue);
      expect(
          File('${pluginsDir.path}/demo_tool/storage.json').readAsStringSync(),
          contains('counter'));

      // 验证偏好与状态已还原
      expect(prefs.getStringList('plugin_toolbox_plugin_order'), ['demo_tool']);
      expect(prefs.getStringList('plugin_toolbox_disabled_plugins'),
          ['demo_tool']);
      expect(prefs.getString('custom_setting'), 'hello');
      expect(registry.pluginOrder, ['demo_tool']);
      expect(registry.disabledPluginIds, contains('demo_tool'));
    });

    test('restoreBackup 安全防御: 拦截包含路径穿越 (Zip Slip) 恶意的压缩包', () async {
      // 伪造包含路径穿越的恶意 ZIP
      final archive = Archive();
      archive.addFile(ArchiveFile(
        'backup_manifest.json',
        utf8
            .encode(const ToolboxBackupManifest(
              timestamp: '2026-10-18T12:00:00Z',
              pluginIds: ['evil'],
            ).toJsonString())
            .length,
        utf8.encode(const ToolboxBackupManifest(
          timestamp: '2026-10-18T12:00:00Z',
          pluginIds: ['evil'],
        ).toJsonString()),
      ));
      archive.addFile(ArchiveFile(
        'plugins/../../evil.sh',
        5,
        utf8.encode('boom!'),
      ));

      final evilZipBytes = ZipEncoder().encode(archive)!;

      expect(
        () => ToolboxBackupService.restoreBackup(
          zipBytes: evilZipBytes,
          pluginsDirectory: pluginsDir,
        ),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('非法的包内相对路径'),
        )),
      );
    });
  });
}
