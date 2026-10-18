// 自动化全模块测试覆盖率收集与合并门禁工具
// 用法: dart run tool/coverage.dart [--no-run] [--min-coverage 80] [--packages core,lua,dui,ui,app]
import 'dart:io';

Future<void> main(List<String> args) async {
  bool runTests = true;
  double minCoverage = 80.0;
  List<String>? selectedModules;

  for (int i = 0; i < args.length; i++) {
    if (args[i] == '--no-run') {
      runTests = false;
    } else if (args[i] == '--min-coverage' && i + 1 < args.length) {
      minCoverage = double.tryParse(args[i + 1]) ?? minCoverage;
    } else if (args[i] == '--packages' && i + 1 < args.length) {
      selectedModules = args[i + 1].split(',').map((e) => e.trim()).toList();
    }
  }

  final modulePaths = <String, String>{
    'packages/core': 'packages/core',
    'packages/lua': 'packages/lua',
    'packages/dui': 'packages/dui',
    'packages/ui': 'packages/ui',
    'app': 'app',
  };

  final targetModules = selectedModules != null
      ? modulePaths.entries
          .where((e) => selectedModules!.any((m) => e.key.contains(m)))
          .toList()
      : modulePaths.entries.toList();

  print('=== PluginToolbox 自动化测试覆盖率采集与汇总 ===\n');

  if (runTests) {
    for (final entry in targetModules) {
      final moduleName = entry.key;
      final moduleDir = entry.value;
      print('🚀 正在运行 $moduleName 测试并生成 coverage/lcov.info ...');
      final result = await Process.run(
        'flutter',
        ['test', '--coverage'],
        workingDirectory: moduleDir,
        runInShell: true,
      );
      if (result.exitCode != 0) {
        print('❌ $moduleName 测试执行失败:');
        print(result.stdout);
        print(result.stderr);
        exit(result.exitCode);
      }
      print('✅ $moduleName 测试执行成功\n');
    }
  }

  // 分析与汇总覆盖率
  print('| 模块 | 发现行数 (LF) | 命中行数 (LH) | 覆盖率 | 状态 |');
  print('|---|---|---|---|---|');

  int totalFound = 0;
  int totalHit = 0;
  final combinedLines = <String>[];
  final missingModules = <String>[];

  for (final entry in targetModules) {
    final moduleName = entry.key;
    final lcovFile = File('${entry.value}/coverage/lcov.info');
    if (!lcovFile.existsSync()) {
      missingModules.add(moduleName);
      print('| $moduleName | - | - | 缺失报告 | ⚠️ 未采集 |');
      continue;
    }

    final lines = lcovFile.readAsLinesSync();
    // 归一化路径，确保合并后的 lcov.info 具有正确的前缀路径
    for (final line in lines) {
      if (line.startsWith('SF:')) {
        final rawPath = line.substring(3).trim();
        final normalized =
            rawPath.startsWith(moduleName) ? rawPath : '$moduleName/$rawPath';
        combinedLines.add('SF:$normalized');
      } else {
        combinedLines.add(line);
      }
    }

    int moduleFound = 0;
    int moduleHit = 0;
    for (final line in lines) {
      if (line.startsWith('LF:')) {
        moduleFound += int.tryParse(line.substring(3).trim()) ?? 0;
      } else if (line.startsWith('LH:')) {
        moduleHit += int.tryParse(line.substring(3).trim()) ?? 0;
      }
    }

    totalFound += moduleFound;
    totalHit += moduleHit;
    final rate = moduleFound == 0 ? 0.0 : (moduleHit / moduleFound) * 100;
    final status = rate >= minCoverage ? '✅ 达标' : '⚠️ 低于阈值';
    print(
        '| $moduleName | $moduleFound | $moduleHit | ${rate.toStringAsFixed(2)}% | $status |');
  }

  final overallRate = totalFound == 0 ? 0.0 : (totalHit / totalFound) * 100;
  print(
      '| **全仓合计** | **$totalFound** | **$totalHit** | **${overallRate.toStringAsFixed(2)}%** | ${overallRate >= minCoverage ? '✅ 通过' : '❌ 阻断'} |');

  if (combinedLines.isNotEmpty) {
    final rootCoverageDir = Directory('coverage');
    if (!rootCoverageDir.existsSync()) {
      rootCoverageDir.createSync(recursive: true);
    }
    File('coverage/lcov.info').writeAsStringSync(combinedLines.join('\n'));
    print('\n已生成全仓合并覆盖率报告: coverage/lcov.info');
  }

  if (missingModules.isNotEmpty) {
    print('\n⚠️ 以下模块未收集到覆盖率: ${missingModules.join(', ')}');
  }
}
