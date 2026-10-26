import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:plugin_toolbox/src/plugin_host/plugin_host_session.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';

class MockUiHandler implements PluginSessionUiHandler {
  final List<PluginPermission> requestedPermissions = [];
  final List<bool> forcePromptFlags = [];
  bool allowPermission = true;

  @override
  Future<bool> requestPermission(
    PluginPermission permission, {
    bool forcePrompt = false,
  }) async {
    requestedPermissions.add(permission);
    forcePromptFlags.add(forcePrompt);
    return allowPermission;
  }

  @override
  void showToast(String message) {}
  @override
  Future<void> showAlert(String title, String message) async {}
  @override
  Future<bool> showConfirm(String title, String message) async => true;
  @override
  Future<String?> showPrompt(
          {required String title, String? hint, String? defaultValue}) async =>
      null;
  @override
  Future<Map<String, dynamic>?> showPickItem(
          {required String title,
          required List<String> items,
          int initialIndex = 0}) async =>
      null;
  @override
  Future<Map<String, dynamic>?> showBottomSheet(
          {required String title, required List<String> items}) async =>
      null;
  @override
  void hideKeyboard() {}
  @override
  Future<String?> pickDate(
          {String? initialDate, String? firstDate, String? lastDate}) async =>
      null;
  @override
  Future<String?> pickTime({String? initialTime}) async => null;
  @override
  Future<bool> openPlugin(String targetPluginId,
          {Map<String, dynamic>? initialData}) async =>
      true;
  @override
  Future<String?> simulateScanBarcode({String? prompt}) async => null;
  @override
  Future<String?> simulateDecodeBarcode() async => null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late DynamicPlugin plugin;
  late MockUiHandler uiHandler;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('session_perm_test_');
    plugin = DynamicPlugin(
      manifest: const PluginManifest(
        id: 'test_perm_plugin',
        name: 'Test Perm Plugin',
        description: 'Test Perm Plugin Description',
        version: '1.0.0',
        author: 'Test Author',
        type: 'lua',
        category: PluginCategory.system,
        entry: 'main.lua',
        ui: 'ui/main.ui.json',
        permissions: [
          PluginPermission.storage,
          PluginPermission.camera,
          PluginPermission.location,
        ],
      ),
      rootDir: tempDir,
    );
    await plugin.initialize(PluginContext(
      pluginId: plugin.id,
      storage: const PluginStorageFactory().create(plugin.id, rootDir: tempDir),
      eventBus: EventBusImpl(),
      logger: Logger(),
      grantedPermissions: {
        PluginPermission.storage,
        PluginPermission.camera,
        PluginPermission.location,
      },
      rootDir: tempDir,
    ));
    uiHandler = MockUiHandler();
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('PluginHostSession 敏感权限首次调用动态确认测试', () {
    test('非敏感已授权权限 (storage) 首次调用不弹窗', () async {
      final session = PluginHostSession(
        plugin: plugin,
        uiHandler: uiHandler,
      );

      final granted = await session.ensurePermission(PluginPermission.storage);
      expect(granted, isTrue);
      expect(uiHandler.requestedPermissions, isEmpty);
    });

    test('敏感权限 (camera) 首次运行时触发二次弹窗确认，后续调用直接放行', () async {
      final session = PluginHostSession(
        plugin: plugin,
        uiHandler: uiHandler,
      );

      // 首次调用 camera：即使 manifest 已声明，因其属于敏感权限，仍需二次弹窗确认
      final firstCheck =
          await session.ensurePermission(PluginPermission.camera);
      expect(firstCheck, isTrue);
      expect(uiHandler.requestedPermissions, [PluginPermission.camera]);
      expect(uiHandler.forcePromptFlags, [true]);

      // 会话内第二次调用 camera：已在本次会话中确认，无需重复打扰用户
      final secondCheck =
          await session.ensurePermission(PluginPermission.camera);
      expect(secondCheck, isTrue);
      expect(uiHandler.requestedPermissions.length, 1);
    });

    test('敏感权限遭用户拒绝后返回 false，后续操作不予放行', () async {
      uiHandler.allowPermission = false;
      final session = PluginHostSession(
        plugin: plugin,
        uiHandler: uiHandler,
      );

      final granted = await session.ensurePermission(PluginPermission.location);
      expect(granted, isFalse);
      expect(uiHandler.requestedPermissions, [PluginPermission.location]);

      final pos = await session.getCurrentPosition();
      expect(pos, isNull);
    });
  });
}
