import 'dart:io';
import 'package:logger/logger.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late PluginContext context;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('diag_test_');

    context = PluginContext(
      pluginId: 'test_diag_plugin',
      storage: const PluginStorageFactory().create(
        'test_diag_plugin',
        rootDir: tempDir,
      ),
      eventBus: EventBusImpl(),
      logger: Logger(),
      grantedPermissions: {PluginPermission.storage, PluginPermission.network},
      rootDir: tempDir,
    );
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('recordDiagnostic 结构化日志持久化落盘并生成 diagnostic.log', () async {
    context.recordDiagnostic(
      DiagnosticLevel.info,
      'InitModule',
      'Plugin initialized successfully',
    );
    context.recordDiagnostic(
      DiagnosticLevel.error,
      'NetworkModule',
      'Connection timed out',
      'SocketTimeoutException',
    );

    final logFile = context.diagnosticLogFile;
    expect(logFile, isNotNull);
    expect(logFile!.existsSync(), isTrue);

    final content = await logFile.readAsString();
    expect(content,
        contains('[INFO ] [InitModule] Plugin initialized successfully'));
    expect(
        content,
        contains(
            '[ERROR] [NetworkModule] Connection timed out | error: SocketTimeoutException'));

    final logsText = context.readDiagnosticLogsText();
    expect(logsText, contains('[InitModule]'));
    expect(logsText, contains('[NetworkModule]'));
  });

  test('diagnostic.log 超出 100KB 时自动滚动备份为 diagnostic.log.old', () async {
    final logFile = File('${tempDir.path}/diagnostic.log');
    await logFile.create(recursive: true);
    // 写入刚好超过 100KB 的填充数据
    final padding = 'A' * (100 * 1024 + 50);
    await logFile.writeAsString('$padding\n');

    expect(logFile.lengthSync(), greaterThanOrEqualTo(100 * 1024));

    // 记录一条新日志触发滚动
    context.recordDiagnostic(
      DiagnosticLevel.warning,
      'DiskCheck',
      'Trigger rolling log archive',
    );

    final oldFile = File('${tempDir.path}/diagnostic.log.old');
    expect(oldFile.existsSync(), isTrue);
    expect(oldFile.lengthSync(), greaterThanOrEqualTo(100 * 1024));

    // 当前 diagnostic.log 已重置并写入新日志
    expect(logFile.existsSync(), isTrue);
    expect(logFile.lengthSync(), lessThan(10 * 1024));
    final newContent = await logFile.readAsString();
    expect(newContent, contains('Trigger rolling log archive'));
  });

  test('generateDiagnosticReport 生成包含配额、权限、审计与日志的完整诊断报告', () async {
    context.recordAuditTrail(
      PluginPermission.storage,
      'read_credentials',
      granted: true,
    );
    context.recordDiagnostic(
      DiagnosticLevel.info,
      'AppSession',
      'Diagnostic report generation test',
    );

    final report = context.generateDiagnosticReport(
      allocatedBytes: 1024 * 512,
      pluginName: '诊断测试插件',
      pluginVersion: '1.0.0',
    );

    expect(report, contains('=== Plugin Diagnostic Report ==='));
    expect(report, contains('Plugin ID: test_diag_plugin'));
    expect(report, contains('Plugin Name: 诊断测试插件'));
    expect(report, contains('Plugin Version: 1.0.0'));
    expect(report, contains('Storage Quota: 50MB'));
    expect(report, contains('Granted Permissions: storage, network'));
    expect(report, contains('--- Audit Trail'));
    expect(report, contains('read_credentials'));
    expect(report, contains('--- Diagnostic Logs ---'));
    expect(report, contains('Diagnostic report generation test'));
  });

  test('clearDiagnosticLogs 同时清除内存列表与磁盘日志文件', () async {
    context.recordDiagnostic(
      DiagnosticLevel.debug,
      'TempTrace',
      'To be cleared',
    );
    final oldFile = File('${tempDir.path}/diagnostic.log.old');
    await oldFile.writeAsString('Old log entries\n');

    expect(context.diagnosticLogs.isNotEmpty, isTrue);
    expect(context.diagnosticLogFile?.existsSync(), isTrue);
    expect(oldFile.existsSync(), isTrue);

    context.clearDiagnosticLogs();

    expect(context.diagnosticLogs.isEmpty, isTrue);
    expect(context.diagnosticLogFile?.existsSync() ?? false, isFalse);
    expect(oldFile.existsSync(), isFalse);
  });
}
