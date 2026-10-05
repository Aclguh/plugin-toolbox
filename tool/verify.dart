// 独立验证脚本: 不依赖 flutter_test, 纯 Dart 直接运行。
// 用法: dart run tool/verify.dart (须在仓库根目录下运行)
import 'dart:convert';
import 'dart:io';
import 'dart:math';

// M-14: 直接导入 packages/core 的生产沙箱路径校验器,
// 断言的是真正运行在用户设备上的安全算法 (该文件为纯 Dart 实现, 无 Flutter 依赖)
import '../packages/core/lib/src/sandbox/sandbox_path.dart';

int _pass = 0;
int _fail = 0;

void expect(bool condition, String label, [String? detail]) {
  if (condition) {
    _pass++;
    print('  OK   $label');
  } else {
    _fail++;
    print('  FAIL $label ${detail != null ? '-> $detail' : ''}');
  }
}

void expectEq(Object? actual, Object? expected, String label) {
  bool isEqual;
  if (actual is List && expected is List) {
    if (actual.length != expected.length) {
      isEqual = false;
    } else {
      isEqual = true;
      for (int i = 0; i < actual.length; i++) {
        if (actual[i] != expected[i]) {
          isEqual = false;
          break;
        }
      }
    }
  } else {
    isEqual = (actual == expected);
  }

  if (isEqual) {
    _pass++;
    print('  OK   $label');
  } else {
    _fail++;
    print('  FAIL $label  -> 实际: $actual  期望: $expected');
  }
}

/// 计算 sRGB 颜色的相对亮度 (Relative Luminance, WCAG 2.1)
double relativeLuminance(int hex) {
  final r = ((hex >> 16) & 0xFF) / 255.0;
  final g = ((hex >> 8) & 0xFF) / 255.0;
  final b = (hex & 0xFF) / 255.0;

  double transform(double c) =>
      c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4).toDouble();

  return 0.2126 * transform(r) + 0.7152 * transform(g) + 0.0722 * transform(b);
}

/// 计算两颜色的对比度
double contrastRatio(int hex1, int hex2) {
  final l1 = relativeLuminance(hex1);
  final l2 = relativeLuminance(hex2);
  final lighter = max(l1, l2);
  final darker = min(l1, l2);
  return (lighter + 0.05) / (darker + 0.05);
}

/// 列表重排测试算法
List<T> simulateReorder<T>(List<T> list, int oldIndex, int newIndex) {
  final copy = List<T>.from(list);
  if (oldIndex < 0 || oldIndex >= copy.length) return copy;
  final item = copy.removeAt(oldIndex);
  final targetIndex = (newIndex > oldIndex) ? newIndex - 1 : newIndex;
  copy.insert(targetIndex.clamp(0, copy.length), item);
  return copy;
}

void main() {
  print('================================================================');
  print('        PluginToolbox 本地规范与逻辑自动化验证套件 (verify.dart)');
  print('================================================================\n');

  // 1. 版本号三处同步校验
  print('--- 1. 版本号同步一致性校验 ---');
  final pubspecFile = File('app/pubspec.yaml');
  expect(pubspecFile.existsSync(), 'app/pubspec.yaml 存在');
  final pubspecContent = pubspecFile.readAsStringSync();
  final versionMatch = RegExp(r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)', multiLine: true)
      .firstMatch(pubspecContent);
  expect(versionMatch != null, 'pubspec.yaml 包含规范的版本号 X.Y.Z+N');

  final versionSemver = versionMatch?.group(1) ?? '';
  print('    检测到宿主版本: $versionSemver');

  final settingsFile = File('app/lib/src/settings/settings_page.dart');
  expect(settingsFile.existsSync(), 'settings_page.dart 存在');
  final settingsContent = settingsFile.readAsStringSync();
  expect(
    settingsContent.contains('版本 $versionSemver'),
    '设置页关于项中展示的版本号与 pubspec.yaml 一致',
    '设置页需包含: 版本 $versionSemver',
  );

  // 版本号第三处同步: widget_test.dart 中的版本断言
  final widgetTestFile = File('app/test/widget_test.dart');
  expect(widgetTestFile.existsSync(), 'app/test/widget_test.dart 存在');
  final widgetTestContent = widgetTestFile.readAsStringSync();
  expect(
    widgetTestContent.contains(versionSemver),
    'widget_test.dart 中包含与 pubspec.yaml 一致的版本断言',
    'widget_test.dart 需包含版本号: $versionSemver',
  );

  // 2. 品牌主题色彩规范与 WCAG AAA 对比度验证
  print('\n--- 2. 品牌主题与 WCAG AAA 对比度断言 ---');
  const bgHex = 0x26366A; // 用户指定主背景色 #26366A
  const fontHex = 0xB4C9FF; // 用户指定主要字体色 #B4C9FF
  const cardHex = 0x1B2445; // 工具箱内槽凹陷卡片色 #1B2445
  const primaryHex = 0x788CFF; // 把手提色 #788CFF

  final bgContrast = contrastRatio(fontHex, bgHex);
  print('    主字体 #B4C9FF 与 主背景 #26366A 对比度: ${bgContrast.toStringAsFixed(2)} : 1');
  expect(
    bgContrast >= 7.0,
    '主字体与背景对比度符合 WCAG AAA 标准 (>= 7.0:1)',
    '当前对比度: ${bgContrast.toStringAsFixed(2)}',
  );

  final cardContrast = contrastRatio(fontHex, cardHex);
  print('    主字体 #B4C9FF 与 卡片底色 #1B2445 对比度: ${cardContrast.toStringAsFixed(2)} : 1');
  expect(
    cardContrast >= 7.0,
    '主字体与卡片容器对比度符合 WCAG AAA 标准 (>= 7.0:1)',
    '当前对比度: ${cardContrast.toStringAsFixed(2)}',
  );

  final colorSchemesFile = File('packages/ui/lib/src/theme/color_schemes.dart');
  expect(colorSchemesFile.existsSync(), 'packages/ui/lib/src/theme/color_schemes.dart 存在');
  final colorSchemesCode = colorSchemesFile.readAsStringSync();

  // 次级文字色 (onSurfaceVariant) 对卡片底色的 AAA 合规 (M-6)
  final onSurfaceVariantMatch =
      RegExp(r'onSurfaceVariant:\s*Color\(0xFF([0-9A-Fa-f]{6})\)').allMatches(colorSchemesCode).toList();
  expect(
    onSurfaceVariantMatch.isNotEmpty &&
        onSurfaceVariantMatch.first.group(1)!.toUpperCase() == '99B2E0',
    '深色主题 onSurfaceVariant 已调亮至 #99B2E0 (WCAG AAA)',
  );
  if (onSurfaceVariantMatch.isNotEmpty) {
    final variantHex = int.parse(onSurfaceVariantMatch.first.group(1)!, radix: 16);
    final variantContrast = contrastRatio(variantHex, cardHex);
    print(
        '    次级文字 #${onSurfaceVariantMatch.first.group(1)} 与 卡片底色 #1B2445 对比度: ${variantContrast.toStringAsFixed(2)} : 1');
    expect(
      variantContrast >= 7.0,
      '次级文字与卡片容器对比度符合 WCAG AAA 标准 (>= 7.0:1)',
      '当前对比度: ${variantContrast.toStringAsFixed(2)}',
    );
  }

  expect(
    colorSchemesCode.contains('0xFF26366A'),
    'color_schemes.dart 声明了 #26366A 品牌主背景色',
  );
  expect(
    colorSchemesCode.contains('0xFFB4C9FF'),
    'color_schemes.dart 声明了 #B4C9FF 品牌主字体色',
  );
  expect(
    colorSchemesCode.contains('0xFF1B2445'),
    'color_schemes.dart 声明了 #1B2445 内槽卡片色',
  );
  expect(
    colorSchemesCode.contains('0xFF788CFF'),
    'color_schemes.dart 声明了 #788CFF 把手与主操作色',
  );

  final appThemeFile = File('packages/ui/lib/src/theme/app_theme.dart');
  expect(appThemeFile.existsSync(), 'app_theme.dart 存在');
  final appThemeCode = appThemeFile.readAsStringSync();
  expect(
    appThemeCode.contains('scaffoldBackgroundColor: scheme.surface'),
    'AppTheme 将脚手架背景绑定至 scheme.surface (#26366A)',
  );
  expect(
    appThemeCode.contains('bodyColor: scheme.onSurface'),
    'AppTheme 全局 TextTheme 绑定至 scheme.onSurface (#B4C9FF)',
  );

  // 3. 架构分层与依赖约束校验 (Monorepo Layering)
  print('\n--- 3. 架构分层单向依赖与纯领域核心约束 ---');
  final coreLibDir = Directory('packages/core/lib');
  expect(coreLibDir.existsSync(), 'packages/core/lib 存在');

  int flutterImportViolations = 0;
  int uiImportViolations = 0;
  int routerImportViolations = 0;
  for (final file in coreLibDir.listSync(recursive: true)) {
    if (file is File && file.path.endsWith('.dart')) {
      final code = file.readAsStringSync();
      if (code.contains("import 'package:flutter/material.dart") ||
          code.contains("import 'package:flutter/cupertino.dart")) {
        flutterImportViolations++;
        print('    [违规] ${file.path} 依赖了 Flutter Material/Cupertino 类库');
      }
      if (code.contains("package:plugin_toolbox_ui/")) {
        uiImportViolations++;
        print('    [违规] ${file.path} 反向依赖了 UI 模块');
      }
      if (code.contains("package:go_router/")) {
        routerImportViolations++;
        print('    [违规] ${file.path} 依赖了 UI 路由框架 go_router');
      }
    }
  }
  expectEq(flutterImportViolations, 0, 'packages/core 严禁依赖 Flutter Material/Cupertino 库 (保持领域层无样式绑定)');
  expectEq(uiImportViolations, 0, 'packages/core 严禁反向依赖 UI 模块');
  expectEq(routerImportViolations, 0, 'packages/core 源码严禁依赖 go_router 路由包');

  final corePubspecFile = File('packages/core/pubspec.yaml');
  expect(corePubspecFile.existsSync(), 'packages/core/pubspec.yaml 存在');
  final corePubspecContent = corePubspecFile.readAsStringSync();
  final hasIllegalPubspecDeps = corePubspecContent.contains('go_router') ||
      corePubspecContent.contains('flutter_riverpod') ||
      corePubspecContent.contains('riverpod_annotation');
  expect(!hasIllegalPubspecDeps, 'packages/core 规范排除 go_router 与 riverpod 等上层框架依赖');

  // 4. 动态插件规范与样例完整性校验
  print('\n--- 4. .ptx 动态插件与 Manifest 规范校验 ---');
  final samplePlugins = ['base64_tool', 'hash_tool'];
  for (final pluginId in samplePlugins) {
    final pluginDir = Directory('sample_plugins/$pluginId');
    expect(pluginDir.existsSync(), '示例插件目录 sample_plugins/$pluginId 存在');

    final manifestF = File('sample_plugins/$pluginId/plugin.json');
    expect(manifestF.existsSync(), '$pluginId: plugin.json 存在');

    Map<String, dynamic>? manifestJson;
    try {
      manifestJson = jsonDecode(manifestF.readAsStringSync()) as Map<String, dynamic>;
    } catch (_) {}
    expect(manifestJson != null, '$pluginId: plugin.json 为有效 JSON');
    expectEq(manifestJson?['id'], pluginId, '$pluginId: plugin.id 匹配目录名');
    expect(manifestJson?['name'] != null && (manifestJson!['name'] as String).isNotEmpty,
        '$pluginId: 包含非空插件名称');
    expect(manifestJson?['version'] != null, '$pluginId: 包含版本号字段');
    expectEq(manifestJson?['type'], 'lua', '$pluginId: 插件类型为 lua');

    final entryRelPath = manifestJson?['entry'] as String? ?? 'main.lua';
    final entryFile = File('sample_plugins/$pluginId/$entryRelPath');
    expect(entryFile.existsSync() && entryFile.lengthSync() > 0, '$pluginId: 入口脚本 $entryRelPath 存在且非空');

    final uiRelPath = manifestJson?['ui'] as String? ?? 'ui/main.ui.json';
    final uiFile = File('sample_plugins/$pluginId/$uiRelPath');
    expect(uiFile.existsSync() && uiFile.lengthSync() > 0, '$pluginId: UI 描述 $uiRelPath 存在且非空');

    Map<String, dynamic>? uiJson;
    try {
      uiJson = jsonDecode(uiFile.readAsStringSync()) as Map<String, dynamic>;
    } catch (_) {}
    expect(uiJson != null, '$pluginId: UI 描述为合法 JSON AST 结构');
    final rootType = uiJson?['type'] as String?;
    expect(
        rootType == 'SingleChildScrollView' || rootType == 'Column' || rootType == 'ListView',
        '$pluginId: 声明式 UI 根节点为合法的顶级布局容器 ($rootType)');

    final ptxFile = File('sample_plugins/$pluginId.ptx');
    expect(ptxFile.existsSync() && ptxFile.lengthSync() > 500, '$pluginId: 打包产物 $pluginId.ptx 存在且有效');
  }

  final packScript = File('sample_plugins/pack.py');
  expect(packScript.existsSync(), '全局插件打包脚本 sample_plugins/pack.py 存在');

  // 5. 沙箱路径隔离与 Path Traversal 防御算法 (直接断言 packages/core 生产实现)
  print('\n--- 5. 沙箱存储与防路径穿越安全算法断言 (生产实现) ---');
  const baseBox = 'app_data/plugins/base64_tool';
  expectEq(SandboxPath.isSafeSubpath(baseBox, 'data/storage.json'), true, '沙箱内合法子路径放行');
  expectEq(SandboxPath.isSafeSubpath(baseBox, 'sub/nested/file.txt'), true, '沙箱多级合法子路径放行');
  expectEq(SandboxPath.isSafeSubpath(baseBox, '../../etc/passwd'), false, '恶意父级穿越路径被成功拦截');
  expectEq(SandboxPath.isSafeSubpath(baseBox, r'..\..\Windows\System32\cmd.exe'), false, 'Windows 风格反斜杠穿越路径拦截');
  expectEq(SandboxPath.isSafeSubpath(baseBox, '....//....//escape'), false, '异形双点混淆路径拦截');
  expectEq(SandboxPath.isSafeSubpath(baseBox, r'C:\evil.bat'), false, 'Windows 盘符绝对路径拦截');
  expectEq(SandboxPath.isSafeSubpath(baseBox, r'C:evil.bat'), false, 'Windows 盘符相对形式拦截');
  expectEq(SandboxPath.isSafeSubpath(baseBox, r'\\server\share\evil'), false, 'UNC 网络共享路径拦截');
  expectEq(SandboxPath.isSafeSubpath(baseBox, '/etc/passwd'), false, 'POSIX 绝对路径不作为相对子路径放行');
  expectEq(SandboxPath.isSafeSubpath(baseBox, ''), false, '空路径不放行');

  // ZIP 解压条目 (Zip Slip) 校验
  expectEq(SandboxPath.isSafeRelativeEntry('ui/main.ui.json'), true, '压缩包合法条目路径放行');
  expectEq(SandboxPath.isSafeRelativeEntry('icon.png'), true, '压缩包根级文件条目放行');
  expectEq(SandboxPath.isSafeRelativeEntry('../evil.txt'), false, '压缩包父级穿越条目拦截');
  expectEq(SandboxPath.isSafeRelativeEntry(r'C:\evil.bat'), false, '压缩包 Windows 盘符条目拦截');
  expectEq(SandboxPath.isSafeRelativeEntry(r'\\server\share\evil'), false, '压缩包 UNC 条目拦截');
  expectEq(SandboxPath.isSafeRelativeEntry('/abs/evil.txt'), false, '压缩包 POSIX 绝对路径条目拦截');
  expectEq(SandboxPath.isSafeRelativeEntry('a/../../evil'), false, '压缩包嵌套穿越条目拦截');
  expectEq(SandboxPath.isSafeRelativeEntry(''), false, '压缩包空条目路径拦截');

  // 6. 双向排序数学一致性算法验证
  print('\n--- 6. 双向排序同步算法逻辑断言 ---');
  final originalList = ['plugin_a', 'plugin_b', 'plugin_c', 'plugin_d'];
  // 模拟将首项移动至索引 2: a, b, c, d -> b, c, a, d
  final reordered1 = simulateReorder(originalList, 0, 3);
  expectEq(reordered1, ['plugin_b', 'plugin_c', 'plugin_a', 'plugin_d'], '前向拖拽重排序');

  // 模拟将末项移动至索引 0: a, b, c, d -> d, a, b, c
  final reordered2 = simulateReorder(originalList, 3, 0);
  expectEq(reordered2, ['plugin_d', 'plugin_a', 'plugin_b', 'plugin_c'], '后向拖拽至首位重排序');

  // 边界移动：原位拖放不变
  final reordered3 = simulateReorder(originalList, 1, 1);
  expectEq(reordered3, originalList, '原位拖放保持序不变');

  // 7. 矢量与位图图标资源完整性
  print('\n--- 7. 矢量图与各分辨率应用图标完整性 ---');
  final iconPng = File('app/assets/icons/plugin-toolbox-icon.png');
  expect(iconPng.existsSync() && iconPng.lengthSync() > 10000, '主图标 PNG 存在且分辨率完备 (>10KB)');

  final iconSvg = File('app/assets/icons/plugin-toolbox-icon.svg');
  expect(iconSvg.existsSync() && iconSvg.lengthSync() > 1000, '矢量图标 SVG 存在且完整');

  final mipmaps = ['mipmap-mdpi', 'mipmap-hdpi', 'mipmap-xhdpi', 'mipmap-xxhdpi', 'mipmap-xxxhdpi'];
  for (final mipmap in mipmaps) {
    final mipmapFile = File('app/android/app/src/main/res/$mipmap/ic_launcher.png');
    expect(mipmapFile.existsSync() && mipmapFile.lengthSync() > 0, 'Android $mipmap 启动图标就绪');
  }

  // 8. 规范与开源证书
  print('\n--- 8. 仓库规范与开源证书校验 ---');
  final gitignore = File('.gitignore');
  expect(gitignore.existsSync(), '.gitignore 存在');
  final gitignoreContent = gitignore.readAsStringSync();
  expect(gitignoreContent.contains('AGENTS.md'), '.gitignore 中排除了本地 AI 规范文件 AGENTS.md');
  expect(gitignoreContent.contains('PTX-plugins/'), '.gitignore 中排除了插件开发目录 PTX-plugins/');

  final license = File('LICENSE');
  expect(license.existsSync(), 'LICENSE 存在');
  final licenseContent = license.readAsStringSync();
  expect(licenseContent.contains('MIT License'), 'LICENSE 为标准的 MIT 开源协议');

  final agentsFile = File('AGENTS.md');
  // AGENTS.md 是本地开发约定文件且被 .gitignore 排除: 开发者本机应存在,
  // CI 干净检出时则必须不存在——两个方向共同验证忽略规则真实生效
  final inCi = Platform.environment['CI'] == 'true' ||
      Platform.environment['GITHUB_ACTIONS'] == 'true';
  if (inCi) {
    expect(!agentsFile.existsSync(), 'CI 干净检出不含本地开发规范指南 AGENTS.md');
  } else {
    expect(agentsFile.existsSync(), '本地存在开发规范指南 AGENTS.md');
  }

  // 总结输出
  print('\n================================================================');
  if (_fail == 0) {
    print('  🎉 全部通过: $_pass 项断言 100% 验证成功！(0 个失败)');
  } else {
    print('  ❌ 验证失败: $_pass 项通过, $_fail 项失败！请按上述日志修复后重试。');
  }
  print('================================================================\n');

  if (_fail > 0) {
    exit(1);
  }
}
