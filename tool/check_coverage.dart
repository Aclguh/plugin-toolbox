// 覆盖率汇总与质量门禁检查脚本
// 用法: dart run tool/check_coverage.dart [--min-coverage 80] [--require-all]
import 'dart:io';

void main(List<String> args) {
  double minCoverage = 70.0;
  bool requireAll = false;
  for (int i = 0; i < args.length; i++) {
    if (args[i] == '--min-coverage' && i + 1 < args.length) {
      minCoverage = double.tryParse(args[i + 1]) ?? minCoverage;
    } else if (args[i] == '--require-all') {
      requireAll = true;
    }
  }

  final packages = <String, String>{
    'packages/core': 'packages/core/coverage/lcov.info',
    'packages/lua': 'packages/lua/coverage/lcov.info',
    'packages/dui': 'packages/dui/coverage/lcov.info',
    'packages/ui': 'packages/ui/coverage/lcov.info',
    'app': 'app/coverage/lcov.info',
  };

  print(
      '=== 代码覆盖率检测与门禁卡点 (最低要求: ${minCoverage.toStringAsFixed(1)}%${requireAll ? ', 严格模式: 全量覆盖率必须具备' : ''}) ===\n');

  int totalFound = 0;
  int totalHit = 0;
  final combinedLines = <String>[];
  bool anyFound = false;
  final missingPackages = <String>[];

  print('| 模块 | 发现行数 (LF) | 命中行数 (LH) | 行覆盖率 | 状态 |');
  print('|---|---|---|---|---|');

  for (final entry in packages.entries) {
    final module = entry.key;
    final lcovPath = entry.value;
    final file = File(lcovPath);

    if (!file.existsSync()) {
      missingPackages.add(module);
      print('| $module | - | - | 缺失 lcov.info | ⚠️ 未采集 |');
      continue;
    }

    anyFound = true;
    final lines = file.readAsLinesSync();
    combinedLines.addAll(lines);

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
    final status = rate >= minCoverage ? '✅ 达标' : '❌ 未达标';
    print(
        '| $module | $moduleFound | $moduleHit | ${rate.toStringAsFixed(2)}% | $status |');
  }

  if (requireAll && missingPackages.isNotEmpty) {
    print(
        '\n❌ 严格模式开启 (--require-all): 以下模块缺失 coverage/lcov.info 覆盖率报告，CI 阻断！');
    for (final m in missingPackages) {
      print('   - $m');
    }
    exit(1);
  }

  if (!anyFound) {
    print('\n⚠️ 未找到任何 coverage/lcov.info 文件。');
    print(
        '请先运行各包的覆盖率采集命令: flutter test --coverage (或 melos run test:coverage)');
    exit(1);
  }

  final overallRate = totalFound == 0 ? 0.0 : (totalHit / totalFound) * 100;
  print(
      '| **总体合计** | **$totalFound** | **$totalHit** | **${overallRate.toStringAsFixed(2)}%** | ${overallRate >= minCoverage ? '✅ 通过' : '❌ 阻断'} |');

  // 保存合并的覆盖率文件
  final combinedDir = Directory('coverage');
  if (!combinedDir.existsSync()) {
    combinedDir.createSync(recursive: true);
  }
  File('coverage/lcov.info').writeAsStringSync(combinedLines.join('\n'));
  print('\n已生成合并覆盖率报告: coverage/lcov.info');

  if (overallRate < minCoverage) {
    print(
        '\n❌ 总体行覆盖率 ${overallRate.toStringAsFixed(2)}% 低于门禁阈值 ${minCoverage.toStringAsFixed(1)}%，CI 阻断！');
    exit(1);
  }

  print('\n🎉 总体行覆盖率 ${overallRate.toStringAsFixed(2)}% 达到门禁要求！');
}
