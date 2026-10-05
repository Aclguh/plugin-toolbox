import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';

void main() {
  group('PluginLoader Tests', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('ptx_loader_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('不存在的 plugins 目录返回空列表', () async {
      final nonExistentDir = Directory('${tempDir.path}/non_existent');
      final plugins = await PluginLoader.loadAllInstalledPlugins(
        baseDirectory: nonExistentDir,
      );
      expect(plugins, isEmpty);
    });

    test('空目录返回空列表', () async {
      final emptyDir = Directory('${tempDir.path}/empty');
      await emptyDir.create();

      final plugins = await PluginLoader.loadAllInstalledPlugins(
        baseDirectory: emptyDir,
      );
      expect(plugins, isEmpty);
    });

    test('正常插件目录成功加载', () async {
      final pluginsDir = Directory('${tempDir.path}/plugins');
      await pluginsDir.create();

      final pluginDir = Directory('${pluginsDir.path}/demo_tool');
      await pluginDir.create();

      final manifestJson = {
        'id': 'demo_tool',
        'name': 'Demo Tool',
        'version': '1.0.0',
        'description': 'A test demo tool',
        'author': 'Tester',
        'type': 'lua',
        'category': 'utility',
        'entry': 'main.lua',
        'ui': 'ui/main.ui.json',
      };
      await File('${pluginDir.path}/plugin.json')
          .writeAsString(jsonEncode(manifestJson));
      await File('${pluginDir.path}/main.lua').writeAsString('-- lua code');

      final plugins = await PluginLoader.loadAllInstalledPlugins(
        baseDirectory: pluginsDir,
      );

      expect(plugins.length, 1);
      expect(plugins.first.id, 'demo_tool');
      expect(plugins.first.name, 'Demo Tool');
      expect(plugins.first.version, '1.0.0');
      expect(plugins.first.isDynamic, isTrue);
    });

    test('损坏的 plugin.json 被跳过并输出警告日志 (不阻断其他合法插件)', () async {
      final pluginsDir = Directory('${tempDir.path}/plugins');
      await pluginsDir.create();

      // 1. 损坏插件
      final corruptedDir = Directory('${pluginsDir.path}/bad_tool');
      await corruptedDir.create();
      await File('${corruptedDir.path}/plugin.json')
          .writeAsString('{ invalid_json: ...');

      // 2. 正常插件
      final goodDir = Directory('${pluginsDir.path}/good_tool');
      await goodDir.create();
      final manifestJson = {
        'id': 'good_tool',
        'name': 'Good Tool',
        'version': '1.0.0',
        'description': 'Good plugin',
        'author': 'Tester',
        'type': 'lua',
        'category': 'utility',
        'entry': 'main.lua',
        'ui': 'ui.json',
      };
      await File('${goodDir.path}/plugin.json')
          .writeAsString(jsonEncode(manifestJson));

      final loggedWarnings = <String>[];
      final testLogger = Logger(
        printer: SimplePrinter(),
        output: _TestLogOutput(loggedWarnings),
      );

      final plugins = await PluginLoader.loadAllInstalledPlugins(
        baseDirectory: pluginsDir,
        logger: testLogger,
      );

      expect(plugins.length, 1);
      expect(plugins.first.id, 'good_tool');
      expect(loggedWarnings.any((w) => w.contains('bad_tool')), isTrue);
    });

    test('非目录实体（普通文件）被安全跳过', () async {
      final pluginsDir = Directory('${tempDir.path}/plugins');
      await pluginsDir.create();

      // 创建一个文件放在 plugins 目录下，而非子目录
      await File('${pluginsDir.path}/random.txt').writeAsString('just a file');

      final plugins = await PluginLoader.loadAllInstalledPlugins(
        baseDirectory: pluginsDir,
      );
      expect(plugins, isEmpty);
    });
  });
}

class _TestLogOutput extends LogOutput {
  final List<String> logs;
  _TestLogOutput(this.logs);

  @override
  void output(OutputEvent event) {
    for (final line in event.lines) {
      logs.add(line);
    }
  }
}
