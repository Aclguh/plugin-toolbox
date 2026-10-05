import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';

void main() {
  group('PermissionManager Tests (P2-3)', () {
    late PermissionManager manager;

    setUp(() {
      manager = PermissionManager();
    });

    test('未授权插件查询返回 false，权限集合为空', () {
      expect(manager.hasPermission('unknown_plugin', PluginPermission.storage), isFalse);
      expect(manager.getPermissions('unknown_plugin'), isEmpty);
    });

    test('initializeForPlugin 正确载入清单中的初始权限', () {
      const manifest = PluginManifest(
        id: 'test_plugin',
        name: 'Test',
        version: '1.0.0',
        description: 'desc',
        author: 'author',
        type: 'lua',
        category: PluginCategory.other,
        permissions: [PluginPermission.storage, PluginPermission.clipboard],
        entry: 'main.lua',
        ui: 'ui.json',
      );

      manager.initializeForPlugin(manifest);
      expect(manager.hasPermission('test_plugin', PluginPermission.storage), isTrue);
      expect(manager.hasPermission('test_plugin', PluginPermission.clipboard), isTrue);
      expect(manager.hasPermission('test_plugin', PluginPermission.network), isFalse);
      expect(manager.getPermissions('test_plugin'), containsAll([
        PluginPermission.storage,
        PluginPermission.clipboard,
      ]));
    });

    test('grantPermissions 动态增补权限且具备幂等性', () {
      manager.grantPermissions('plugin_a', [PluginPermission.network]);
      expect(manager.hasPermission('plugin_a', PluginPermission.network), isTrue);

      // 重复授权保持幂等，不产生重复或异常
      manager.grantPermissions('plugin_a', [PluginPermission.network, PluginPermission.storage]);
      expect(manager.hasPermission('plugin_a', PluginPermission.network), isTrue);
      expect(manager.hasPermission('plugin_a', PluginPermission.storage), isTrue);
      expect(manager.getPermissions('plugin_a').length, 2);
    });

    test('revokePermission 撤销指定权限', () {
      manager.grantPermissions('plugin_a', [
        PluginPermission.network,
        PluginPermission.storage,
      ]);

      manager.revokePermission('plugin_a', PluginPermission.network);
      expect(manager.hasPermission('plugin_a', PluginPermission.network), isFalse);
      expect(manager.hasPermission('plugin_a', PluginPermission.storage), isTrue);

      // 撤销未授权权限不抛异常
      expect(() => manager.revokePermission('plugin_a', PluginPermission.clipboard), returnsNormally);
      expect(() => manager.revokePermission('non_existent', PluginPermission.network), returnsNormally);
    });

    test('clearForPlugin 清理全部权限', () {
      manager.grantPermissions('plugin_a', [
        PluginPermission.network,
        PluginPermission.storage,
      ]);

      manager.clearForPlugin('plugin_a');
      expect(manager.hasPermission('plugin_a', PluginPermission.network), isFalse);
      expect(manager.hasPermission('plugin_a', PluginPermission.storage), isFalse);
      expect(manager.getPermissions('plugin_a'), isEmpty);
    });

    test('getPermissions 返回不可修改的只读集合', () {
      manager.grantPermissions('plugin_a', [PluginPermission.storage]);
      final perms = manager.getPermissions('plugin_a');

      expect(() => perms.add(PluginPermission.network), throwsUnsupportedError);
    });

    test('PluginPermission 字符串解析支持新增的系统权限 (torch, sensor, notification)', () {
      expect(PluginPermission.fromString('torch'), PluginPermission.torch);
      expect(PluginPermission.fromString('TORCH'), PluginPermission.torch);
      expect(PluginPermission.fromString('sensor'), PluginPermission.sensor);
      expect(PluginPermission.fromString('notification'), PluginPermission.notification);
      expect(PluginPermission.fromString('unknown_perm'), isNull);
    });
  });
}
