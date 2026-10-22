import 'package:logger/logger.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';

void main() {
  group('PermissionManager Tests (P2-3)', () {
    late PermissionManager manager;

    setUp(() {
      manager = PermissionManager();
    });

    test('未授权插件查询返回 false，权限集合为空', () {
      expect(manager.hasPermission('unknown_plugin', PluginPermission.storage),
          isFalse);
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
      expect(manager.hasPermission('test_plugin', PluginPermission.storage),
          isTrue);
      expect(manager.hasPermission('test_plugin', PluginPermission.clipboard),
          isTrue);
      expect(manager.hasPermission('test_plugin', PluginPermission.network),
          isFalse);
      expect(
          manager.getPermissions('test_plugin'),
          containsAll([
            PluginPermission.storage,
            PluginPermission.clipboard,
          ]));
    });

    test('grantPermissions 动态增补权限且具备幂等性', () {
      manager.grantPermissions('plugin_a', [PluginPermission.network]);
      expect(
          manager.hasPermission('plugin_a', PluginPermission.network), isTrue);

      // 重复授权保持幂等，不产生重复或异常
      manager.grantPermissions(
          'plugin_a', [PluginPermission.network, PluginPermission.storage]);
      expect(
          manager.hasPermission('plugin_a', PluginPermission.network), isTrue);
      expect(
          manager.hasPermission('plugin_a', PluginPermission.storage), isTrue);
      expect(manager.getPermissions('plugin_a').length, 2);
    });

    test('revokePermission 撤销指定权限', () {
      manager.grantPermissions('plugin_a', [
        PluginPermission.network,
        PluginPermission.storage,
      ]);

      manager.revokePermission('plugin_a', PluginPermission.network);
      expect(
          manager.hasPermission('plugin_a', PluginPermission.network), isFalse);
      expect(
          manager.hasPermission('plugin_a', PluginPermission.storage), isTrue);

      // 撤销未授权权限不抛异常
      expect(
          () =>
              manager.revokePermission('plugin_a', PluginPermission.clipboard),
          returnsNormally);
      expect(
          () => manager.revokePermission(
              'non_existent', PluginPermission.network),
          returnsNormally);
    });

    test('clearForPlugin 清理全部权限', () {
      manager.grantPermissions('plugin_a', [
        PluginPermission.network,
        PluginPermission.storage,
      ]);

      manager.clearForPlugin('plugin_a');
      expect(
          manager.hasPermission('plugin_a', PluginPermission.network), isFalse);
      expect(
          manager.hasPermission('plugin_a', PluginPermission.storage), isFalse);
      expect(manager.getPermissions('plugin_a'), isEmpty);
    });

    test('getPermissions 返回不可修改的只读集合', () {
      manager.grantPermissions('plugin_a', [PluginPermission.storage]);
      final perms = manager.getPermissions('plugin_a');

      expect(() => perms.add(PluginPermission.network), throwsUnsupportedError);
    });

    test(
        'PluginPermission 字符串解析支持系统权限 (torch, sensor, notification, biometrics, microphone)',
        () {
      expect(PluginPermission.fromString('torch'), PluginPermission.torch);
      expect(PluginPermission.fromString('TORCH'), PluginPermission.torch);
      expect(PluginPermission.fromString('sensor'), PluginPermission.sensor);
      expect(PluginPermission.fromString('notification'),
          PluginPermission.notification);
      expect(PluginPermission.fromString('biometrics'),
          PluginPermission.biometrics);
      expect(PluginPermission.fromString('microphone'),
          PluginPermission.microphone);
      expect(PluginPermission.fromString('unknown_perm'), isNull);
    });

    test('PermissionManager 支持覆盖设置、导入导出与非敏感权限合并', () {
      manager.setPermissions('plugin_b', [PluginPermission.camera]);
      expect(manager.hasCustomPermissions('plugin_b'), isTrue);
      expect(manager.hasCustomPermissions('plugin_c'), isFalse);

      manager.mergeNonSensitive('plugin_b', [
        PluginPermission.clipboard, // 非敏感
        PluginPermission.location, // 敏感
      ]);
      expect(manager.hasPermission('plugin_b', PluginPermission.clipboard),
          isTrue);
      expect(manager.hasPermission('plugin_b', PluginPermission.location),
          isFalse);

      final exported = manager.toMap();
      expect(exported['plugin_b'], contains(PluginPermission.camera));
      expect(exported['plugin_b'], contains(PluginPermission.clipboard));

      final manager2 = PermissionManager();
      manager2.loadFromMap(exported);
      expect(
          manager2.hasPermission('plugin_b', PluginPermission.camera), isTrue);
      expect(manager2.hasPermission('plugin_b', PluginPermission.clipboard),
          isTrue);
    });
    test('PluginContext.recordAuditTrail 记录权限安全审计事件与队列上限控制', () {
      final context = PluginContext(
        pluginId: 'audit_plugin',
        storage: const PluginStorageFactory().create('audit_plugin'),
        eventBus: EventBusImpl(),
        logger: Logger(),
        grantedPermissions: {PluginPermission.storage},
      );

      // 查询已授权权限并附带 auditAction
      expect(
        context.hasPermission(PluginPermission.storage,
            auditAction: 'read_file'),
        isTrue,
      );
      expect(context.auditTrail.length, 1);
      final r1 = context.auditTrail.first;
      expect(r1.permission, PluginPermission.storage);
      expect(r1.action, 'read_file');
      expect(r1.granted, isTrue);
      expect(r1.toString(), contains('[ALLOW] [storage] read_file'));

      // 查询未授权权限并附带 auditAction
      expect(
        context.hasPermission(PluginPermission.network,
            auditAction: 'http_get', detail: 'https://evil.com'),
        isFalse,
      );
      expect(context.auditTrail.length, 2);
      final r2 = context.auditTrail[1];
      expect(r2.permission, PluginPermission.network);
      expect(r2.granted, isFalse);
      expect(r2.detail, 'https://evil.com');
      expect(r2.toString(),
          contains('[DENY] [network] http_get (https://evil.com)'));

      // 诊断日志同步接收审计条目
      expect(context.diagnosticLogs.any((l) => l.contains('[AUDIT]')), isTrue);

      // 验证队列上限为 100 条
      for (var i = 0; i < 120; i++) {
        context.recordAuditTrail(PluginPermission.clipboard, 'copy_$i');
      }
      expect(context.auditTrail.length, 100);
      expect(context.auditTrail.last.action, 'copy_119');

      // 清空
      context.clearAuditTrail();
      expect(context.auditTrail, isEmpty);
    });
  });
}
