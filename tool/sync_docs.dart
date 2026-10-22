// 自动化测试用例统计与 README.md 文档同步工具
// 用法: dart run tool/sync_docs.dart
import 'dart:io';

void main() {
  final casePattern = RegExp(r'\b(?:test|testWidgets)\(');
  const moduleTestDirs = <String, String>{
    'packages/core': 'packages/core/test',
    'packages/lua': 'packages/lua/test',
    'packages/dui': 'packages/dui/test',
    'packages/ui': 'packages/ui/test',
    'app': 'app/test',
  };

  final perModuleCases = <String, int>{};
  var totalCases = 0;

  moduleTestDirs.forEach((module, dirPath) {
    final dir = Directory(dirPath);
    var count = 0;
    if (dir.existsSync()) {
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is File && entity.path.endsWith('_test.dart')) {
          count += casePattern.allMatches(entity.readAsStringSync()).length;
        }
      }
    }
    perModuleCases[module] = count;
    totalCases += count;
  });

  final modules = moduleTestDirs.keys.toList();
  final breakdown = modules.map((m) => '$m ${perModuleCases[m]}').join(' / ');
  print('📊 当前真实测试统计: $breakdown, 共 $totalCases 用例');

  final readmeFile = File('README.md');
  if (!readmeFile.existsSync()) {
    print('❌ 未找到 README.md');
    exit(1);
  }

  var content = readmeFile.readAsStringSync();
  final totalRegex = RegExp(r'共\s*\d+\s*用例');
  final breakdownRegex = RegExp(
    r'packages/core\s+\d+\s*/\s*packages/lua\s+\d+\s*/\s*packages/dui\s+\d+\s*/\s*packages/ui\s+\d+\s*/\s*app\s+\d+',
  );

  final newTotalStr = '共 $totalCases 用例';
  final newBreakdownStr =
      'packages/core ${perModuleCases['packages/core']} / packages/lua ${perModuleCases['packages/lua']} / packages/dui ${perModuleCases['packages/dui']} / packages/ui ${perModuleCases['packages/ui']} / app ${perModuleCases['app']}';

  bool changed = false;
  if (totalRegex.hasMatch(content)) {
    content = content.replaceFirst(totalRegex, newTotalStr);
    changed = true;
  }
  if (breakdownRegex.hasMatch(content)) {
    content = content.replaceFirst(breakdownRegex, newBreakdownStr);
    changed = true;
  }

  if (changed) {
    readmeFile.writeAsStringSync(content, flush: true);
    print('✅ README.md 测试用例数已同步更新为: $newTotalStr ($newBreakdownStr)');
  } else {
    print('ℹ️ README.md 内容已是一致，无需修改');
  }
}
