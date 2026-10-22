// 独立验证脚本: 不依赖 flutter_test, 纯 Dart 直接运行。
// 用法: dart run tool/verify.dart (须在仓库根目录下运行)
import 'dart:convert';
import 'dart:io';
import 'dart:math';

// M-14: 直接导入 packages/core 的生产沙箱路径校验器,
// 断言的是真正运行在用户设备上的安全算法 (该文件为纯 Dart 实现, 无 Flutter 依赖)
import '../packages/core/lib/src/sandbox/sandbox_path.dart';
// 插件商店的版本语义同样直接断言生产实现 (纯 Dart, 无 Flutter 依赖)
import '../packages/core/lib/src/store/plugin_store_semantics.dart';
// M-18: 双向排序一致性直接驱动生产排序控制器 (纯 Dart, 无 Flutter 依赖),
// 不再在脚本内复制仿真算法, 生产 reorder 行为改坏时本节立即 FAIL
import '../packages/core/lib/src/plugin/plugin_list_controller.dart';

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

void main(List<String> args) {
  print('================================================================');
  print('        PluginToolbox 本地规范与逻辑自动化验证套件 (verify.dart)');
  print('================================================================\n');

  // 1. 版本号三处同步校验
  print('--- 1. 版本号同步一致性校验 ---');
  final pubspecFile = File('app/pubspec.yaml');
  expect(pubspecFile.existsSync(), 'app/pubspec.yaml 存在');
  final pubspecContent = pubspecFile.readAsStringSync();
  final versionMatch =
      RegExp(r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)', multiLine: true)
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

  final bgContrast = contrastRatio(fontHex, bgHex);
  print(
      '    主字体 #B4C9FF 与 主背景 #26366A 对比度: ${bgContrast.toStringAsFixed(2)} : 1');
  expect(
    bgContrast >= 7.0,
    '主字体与背景对比度符合 WCAG AAA 标准 (>= 7.0:1)',
    '当前对比度: ${bgContrast.toStringAsFixed(2)}',
  );

  final cardContrast = contrastRatio(fontHex, cardHex);
  print(
      '    主字体 #B4C9FF 与 卡片底色 #1B2445 对比度: ${cardContrast.toStringAsFixed(2)} : 1');
  expect(
    cardContrast >= 7.0,
    '主字体与卡片容器对比度符合 WCAG AAA 标准 (>= 7.0:1)',
    '当前对比度: ${cardContrast.toStringAsFixed(2)}',
  );

  final colorSchemesFile = File('packages/ui/lib/src/theme/color_schemes.dart');
  expect(colorSchemesFile.existsSync(),
      'packages/ui/lib/src/theme/color_schemes.dart 存在');
  final colorSchemesCode = colorSchemesFile.readAsStringSync();

  // 次级文字色 (onSurfaceVariant) 对卡片底色的 AAA 合规 (M-6)
  final onSurfaceVariantMatch =
      RegExp(r'onSurfaceVariant:\s*Color\(\s*0xFF([0-9A-Fa-f]{6})\s*\)')
          .allMatches(colorSchemesCode)
          .toList();
  expect(
    onSurfaceVariantMatch.isNotEmpty &&
        onSurfaceVariantMatch.first.group(1)!.toUpperCase() == '99B2E0',
    '深色主题 onSurfaceVariant 已调亮至 #99B2E0 (WCAG AAA)',
  );
  if (onSurfaceVariantMatch.isNotEmpty) {
    final variantHex =
        int.parse(onSurfaceVariantMatch.first.group(1)!, radix: 16);
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
      if (code.contains('package:plugin_toolbox_ui/')) {
        uiImportViolations++;
        print('    [违规] ${file.path} 反向依赖了 UI 模块');
      }
      if (code.contains('package:go_router/')) {
        routerImportViolations++;
        print('    [违规] ${file.path} 依赖了 UI 路由框架 go_router');
      }
    }
  }
  expectEq(flutterImportViolations, 0,
      'packages/core 严禁依赖 Flutter Material/Cupertino 库 (保持领域层无样式绑定)');
  expectEq(uiImportViolations, 0, 'packages/core 严禁反向依赖 UI 模块');
  expectEq(routerImportViolations, 0, 'packages/core 源码严禁依赖 go_router 路由包');

  final corePubspecFile = File('packages/core/pubspec.yaml');
  expect(corePubspecFile.existsSync(), 'packages/core/pubspec.yaml 存在');
  final corePubspecContent = corePubspecFile.readAsStringSync();
  final hasIllegalPubspecDeps = corePubspecContent.contains('go_router') ||
      corePubspecContent.contains('flutter_riverpod') ||
      corePubspecContent.contains('riverpod_annotation');
  expect(!hasIllegalPubspecDeps,
      'packages/core 规范排除 go_router 与 riverpod 等上层框架依赖');

  final duiPubspecFile = File('packages/dui/pubspec.yaml');
  expect(duiPubspecFile.existsSync(), 'packages/dui/pubspec.yaml 存在');
  final duiPubspecContent = duiPubspecFile.readAsStringSync();
  final duiHasLuaDep = duiPubspecContent.contains('plugin_toolbox_lua');
  expect(!duiHasLuaDep, 'packages/dui 严禁依赖 packages/lua 模块 (保持兄弟模块单向解耦)');

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
      manifestJson =
          jsonDecode(manifestF.readAsStringSync()) as Map<String, dynamic>;
    } catch (_) {
      // 容错: 脏数据保持 null, 交由下方断言给出 FAIL
    }
    expect(manifestJson != null, '$pluginId: plugin.json 为有效 JSON');
    expectEq(manifestJson?['id'], pluginId, '$pluginId: plugin.id 匹配目录名');
    expect(
        manifestJson?['name'] != null &&
            (manifestJson!['name'] as String).isNotEmpty,
        '$pluginId: 包含非空插件名称');
    expect(manifestJson?['version'] != null, '$pluginId: 包含版本号字段');
    expectEq(manifestJson?['type'], 'lua', '$pluginId: 插件类型为 lua');

    final entryRelPath = manifestJson?['entry'] as String? ?? 'main.lua';
    final entryFile = File('sample_plugins/$pluginId/$entryRelPath');
    expect(entryFile.existsSync() && entryFile.lengthSync() > 0,
        '$pluginId: 入口脚本 $entryRelPath 存在且非空');

    final uiRelPath = manifestJson?['ui'] as String? ?? 'ui/main.ui.json';
    final uiFile = File('sample_plugins/$pluginId/$uiRelPath');
    expect(uiFile.existsSync() && uiFile.lengthSync() > 0,
        '$pluginId: UI 描述 $uiRelPath 存在且非空');

    Map<String, dynamic>? uiJson;
    try {
      uiJson = jsonDecode(uiFile.readAsStringSync()) as Map<String, dynamic>;
    } catch (_) {
      // 容错: 脏数据保持 null, 交由下方断言给出 FAIL
    }
    expect(uiJson != null, '$pluginId: UI 描述为合法 JSON AST 结构');
    final rootType = uiJson?['type'] as String?;
    expect(
        rootType == 'SingleChildScrollView' ||
            rootType == 'Column' ||
            rootType == 'ListView',
        '$pluginId: 声明式 UI 根节点为合法的顶级布局容器 ($rootType)');

    final ptxFile = File('sample_plugins/$pluginId.ptx');
    expect(ptxFile.existsSync() && ptxFile.lengthSync() > 500,
        '$pluginId: 打包产物 $pluginId.ptx 存在且有效');
  }

  final packScript = File('sample_plugins/pack.py');
  expect(packScript.existsSync(), '全局插件打包脚本 sample_plugins/pack.py 存在');

  final pluginSchemaFile = File('tool/schemas/plugin.schema.json');
  expect(pluginSchemaFile.existsSync(),
      '插件清单 JSON Schema 规范文件 plugin.schema.json 存在');
  Map<String, dynamic>? pluginSchemaJson;
  try {
    pluginSchemaJson = jsonDecode(pluginSchemaFile.readAsStringSync())
        as Map<String, dynamic>?;
  } catch (_) {}
  expect(pluginSchemaJson != null && pluginSchemaJson['properties'] != null,
      'plugin.schema.json 结构完整且为合法 JSON Schema');

  final duiSchemaFile = File('tool/schemas/dui.schema.json');
  expect(duiSchemaFile.existsSync(),
      'DUI 声明式组件树 JSON Schema 规范文件 dui.schema.json 存在');
  Map<String, dynamic>? duiSchemaJson;
  try {
    duiSchemaJson =
        jsonDecode(duiSchemaFile.readAsStringSync()) as Map<String, dynamic>?;
  } catch (_) {}
  expect(duiSchemaJson != null && duiSchemaJson['properties'] != null,
      'dui.schema.json 结构完整且为合法 JSON Schema');

  // 校验 DUI Schema 双向对齐门禁
  final duiSchemaData = duiSchemaJson as Map<String, dynamic>;
  final schemaEnum =
      ((duiSchemaData['properties'] as Map)['type']['enum'] as List)
          .cast<String>()
          .toSet();

  final factoryPattern = RegExp(r"registerFactory\('([a-zA-Z0-9_]+)'");
  final registeredFactories = <String>{};
  final factoriesDir = Directory('packages/dui/lib/src/factories');
  if (factoriesDir.existsSync()) {
    for (final entity in factoriesDir.listSync()) {
      if (entity is File && entity.path.endsWith('.dart')) {
        for (final m in factoryPattern.allMatches(entity.readAsStringSync())) {
          registeredFactories.add(m.group(1)!);
        }
      }
    }
  }
  final missingInSchema = registeredFactories.difference(schemaEnum);
  expect(
    missingInSchema.isEmpty,
    'packages/dui 注册的所有组件工厂在 dui.schema.json 中均有合法声明',
    '未在 Schema 声明的组件: $missingInSchema',
  );

  final luaDefFile = File('tool/schemas/plugin_api.def.lua');
  expect(
      luaDefFile.existsSync(), '官方 EmmyLua/LuaLS 类型定义文件 plugin_api.def.lua 存在');
  final luaDefContent =
      luaDefFile.existsSync() ? luaDefFile.readAsStringSync() : '';
  final emmyNamespaces = RegExp(r'^([a-zA-Z0-9_]+)\s*=\s*\{\}', multiLine: true)
      .allMatches(luaDefContent)
      .map((m) => m.group(1)!)
      .toSet();
  const expectedHostApis = [
    'state',
    'clipboard',
    'storage',
    'network',
    'dialog',
    'codec',
    'json',
    'hash',
    'util',
    'system',
    'haptic',
    'ui',
    'share',
    'media',
    'fs',
    'crypto',
    'regex',
    'color',
    'archive',
    'document',
    'torch',
    'qrcode',
    'camera',
    'vision',
    'sensor',
    'image',
    'notification',
    'audio',
    'socket',
    'websocket',
    'biometrics',
    'task',
    'screen',
    'location',
    'nfc',
    'bluetooth',
    'database',
    'ai',
    'ipc',
    'i18n',
    'timer',
  ];
  final missingHostApis =
      expectedHostApis.where((ns) => !emmyNamespaces.contains(ns)).toList();
  expect(
    missingHostApis.isEmpty,
    'plugin_api.def.lua 完整定义了全部核心宿主 API 命名空间',
    '缺失定义的 API 命名空间: $missingHostApis',
  );

  final ptxCliFile = File('tool/ptx.py');
  expect(ptxCliFile.existsSync(), '官方插件开发者脚手架 CLI tool/ptx.py 存在');
  final ptxPyContent = ptxCliFile.readAsStringSync();
  expect(
    ptxPyContent.contains('"ref": "input_text"') &&
        !ptxPyContent.contains('"stateKey": "input_text"'),
    'ptx.py 模板严格使用 ref 属性进行双向绑定 (消除属性漂移)',
  );

  final installerFile =
      File('packages/core/lib/src/installer/plugin_installer.dart');
  expect(installerFile.existsSync(), 'PluginInstaller 源码存在');
  final installerCode = installerFile.readAsStringSync();
  expect(
    installerCode.contains('exportToBytes') &&
        installerCode.contains('exportToPtx'),
    'PluginInstaller 支持已安装插件导出为 .ptx 归档包',
  );
  expect(
    installerCode.contains('_shouldExcludeFromExport') &&
        installerCode.contains('storage.json'),
    '导出包自动排除沙箱持久化存储与备份文件',
  );

  // 5. 沙箱路径隔离与 Path Traversal 防御算法 (直接断言 packages/core 生产实现)
  print('\n--- 5. 沙箱存储与防路径穿越安全算法断言 (生产实现) ---');
  const baseBox = 'app_data/plugins/base64_tool';
  expectEq(SandboxPath.isSafeSubpath(baseBox, 'data/storage.json'), true,
      '沙箱内合法子路径放行');
  expectEq(SandboxPath.isSafeSubpath(baseBox, 'sub/nested/file.txt'), true,
      '沙箱多级合法子路径放行');
  expectEq(SandboxPath.isSafeSubpath(baseBox, '../../etc/passwd'), false,
      '恶意父级穿越路径被成功拦截');
  expectEq(
      SandboxPath.isSafeSubpath(baseBox, r'..\..\Windows\System32\cmd.exe'),
      false,
      'Windows 风格反斜杠穿越路径拦截');
  expectEq(SandboxPath.isSafeSubpath(baseBox, '....//....//escape'), false,
      '异形双点混淆路径拦截');
  expectEq(SandboxPath.isSafeSubpath(baseBox, r'C:\evil.bat'), false,
      'Windows 盘符绝对路径拦截');
  expectEq(SandboxPath.isSafeSubpath(baseBox, r'C:evil.bat'), false,
      'Windows 盘符相对形式拦截');
  expectEq(SandboxPath.isSafeSubpath(baseBox, r'\\server\share\evil'), false,
      'UNC 网络共享路径拦截');
  expectEq(SandboxPath.isSafeSubpath(baseBox, '/etc/passwd'), false,
      'POSIX 绝对路径不作为相对子路径放行');
  expectEq(SandboxPath.isSafeSubpath(baseBox, ''), false, '空路径不放行');

  // ZIP 解压条目 (Zip Slip) 校验
  expectEq(
      SandboxPath.isSafeRelativeEntry('ui/main.ui.json'), true, '压缩包合法条目路径放行');
  expectEq(SandboxPath.isSafeRelativeEntry('icon.png'), true, '压缩包根级文件条目放行');
  expectEq(
      SandboxPath.isSafeRelativeEntry('../evil.txt'), false, '压缩包父级穿越条目拦截');
  expectEq(SandboxPath.isSafeRelativeEntry(r'C:\evil.bat'), false,
      '压缩包 Windows 盘符条目拦截');
  expectEq(SandboxPath.isSafeRelativeEntry(r'\\server\share\evil'), false,
      '压缩包 UNC 条目拦截');
  expectEq(SandboxPath.isSafeRelativeEntry('/abs/evil.txt'), false,
      '压缩包 POSIX 绝对路径条目拦截');
  expectEq(
      SandboxPath.isSafeRelativeEntry('a/../../evil'), false, '压缩包嵌套穿越条目拦截');
  expectEq(SandboxPath.isSafeRelativeEntry(''), false, '压缩包空条目路径拦截');

  // Lua 预编译字节码拦截
  expectEq(SandboxPath.isLuaBytecode([0x1B, 0x4C, 0x75, 0x61, 0x01]), true,
      '预编译 Lua 字节码魔数被成功识别');
  expectEq(SandboxPath.isLuaBytecode([0x1B, 0x4C, 0x75]), false, '非完整字节码魔数不误判');
  expectEq(
      SandboxPath.isLuaBytecode('print("hello")'.codeUnits), false, '源码文本放行通过');

  // 6. 双向排序数学一致性算法验证 (直接断言 packages/core 生产实现)
  print('\n--- 6. 双向排序同步算法逻辑断言 (生产实现) ---');
  // 锚定调用链: 注册中心必须把两处排序入口委托给同一个 PluginListController,
  // 保证下方驱动的就是真正运行在用户设备上的排序算法
  final listControllerFile =
      File('packages/core/lib/src/plugin/plugin_list_controller.dart');
  expect(listControllerFile.existsSync(),
      '生产排序控制器 plugin_list_controller.dart 存在');

  final registryFile =
      File('packages/core/lib/src/plugin/plugin_registry.dart');
  expect(registryFile.existsSync(), 'plugin_registry.dart 存在');
  final registryCode = registryFile.readAsStringSync();
  expect(
    registryCode.contains('_orderController.reorder(oldIndex, newIndex)') &&
        registryCode.contains('_orderController.reorderEnabled('),
    'PluginRegistry 将全量/启用子集排序统一委托给 PluginListController',
  );

  // 锚定宿主两处入口: 插件管理中心全量重排, 主界面网格仅重排启用子集
  final managerPageCode =
      File('app/lib/src/plugin_manager/plugin_manager_page.dart')
          .readAsStringSync();
  expect(
    managerPageCode.contains('.reorder(oldIndex, newIndex)'),
    '插件管理中心拖拽走全量列表重排 reorder',
  );
  final homePageCode =
      File('app/lib/src/home/home_page.dart').readAsStringSync();
  expect(
    homePageCode.contains('.reorderEnabled(oldIndex, newIndex)'),
    '主界面网格拖拽走启用子集重排 reorderEnabled',
  );

  // 两处排序经同一 Riverpod Notifier 入口落盘, 保证双向变动实时同步持久化
  final providersCode =
      File('app/lib/src/providers/app_providers.dart').readAsStringSync();
  expect(
    providersCode.contains('state.reorder(oldIndex, newIndex)') &&
        providersCode.contains('state.reorderEnabled(oldIndex, newIndex)') &&
        providersCode.contains('saveOrder()'),
    '两处排序经同一 Notifier 入口并实时 saveOrder 持久化',
  );

  PluginListController newController(List<String> ids) {
    final controller = PluginListController();
    controller.loadOrder(ids.toSet(), const []);
    return controller;
  }

  const baseOrder = ['plugin_a', 'plugin_b', 'plugin_c', 'plugin_d'];

  // 全量重排 (插件管理中心): 项目索引语义, 移除后直接插入目标位
  final forward = newController(baseOrder);
  forward.reorder(0, 3);
  expectEq(forward.order, ['plugin_b', 'plugin_c', 'plugin_d', 'plugin_a'],
      '全量重排: 首项前向拖拽至末位');

  final backward = newController(baseOrder);
  backward.reorder(3, 0);
  expectEq(backward.order, ['plugin_d', 'plugin_a', 'plugin_b', 'plugin_c'],
      '全量重排: 末项后向拖拽至首位');

  final inPlace = newController(baseOrder);
  inPlace.reorder(1, 1);
  expectEq(inPlace.order, baseOrder, '全量重排: 原位拖放保持序不变');

  final outOfBounds = newController(baseOrder);
  outOfBounds.reorder(-1, 2);
  outOfBounds.reorder(1, 4);
  expectEq(outOfBounds.order, baseOrder, '全量重排: 越界索引被安全忽略');

  // 启用子集重排 (主界面网格): 禁用插件 (plugin_x/plugin_y) 相对位置保持不变
  const mixedOrder = [
    'plugin_a',
    'plugin_x',
    'plugin_b',
    'plugin_y',
    'plugin_c'
  ];
  const enabledSubset = ['plugin_a', 'plugin_b', 'plugin_c'];

  final gridForward = newController(mixedOrder);
  gridForward.reorderEnabled(enabledSubset, 0, 2);
  expectEq(
    gridForward.order,
    ['plugin_x', 'plugin_b', 'plugin_y', 'plugin_c', 'plugin_a'],
    '启用子集重排: 前向拖拽且禁用插件相对位置不变',
  );

  final gridBackward = newController(mixedOrder);
  gridBackward.reorderEnabled(enabledSubset, 2, 0);
  expectEq(
    gridBackward.order,
    ['plugin_c', 'plugin_a', 'plugin_x', 'plugin_b', 'plugin_y'],
    '启用子集重排: 后向拖拽且禁用插件相对位置不变',
  );

  // 7. 矢量与位图图标资源完整性
  print('\n--- 7. 矢量图与各分辨率应用图标完整性 ---');
  final iconPng = File('app/assets/icons/plugin-toolbox-icon.png');
  expect(iconPng.existsSync() && iconPng.lengthSync() > 10000,
      '主图标 PNG 存在且分辨率完备 (>10KB)');

  final iconSvg = File('app/assets/icons/plugin-toolbox-icon.svg');
  expect(iconSvg.existsSync() && iconSvg.lengthSync() > 1000, '矢量图标 SVG 存在且完整');

  final mipmaps = [
    'mipmap-mdpi',
    'mipmap-hdpi',
    'mipmap-xhdpi',
    'mipmap-xxhdpi',
    'mipmap-xxxhdpi'
  ];
  for (final mipmap in mipmaps) {
    final mipmapFile =
        File('app/android/app/src/main/res/$mipmap/ic_launcher.png');
    expect(mipmapFile.existsSync() && mipmapFile.lengthSync() > 0,
        'Android $mipmap 启动图标就绪');
  }

  // 8. 规范与开源证书
  print('\n--- 8. 仓库规范与开源证书校验 ---');
  final gitignore = File('.gitignore');
  expect(gitignore.existsSync(), '.gitignore 存在');
  final gitignoreContent = gitignore.readAsStringSync();
  expect(gitignoreContent.contains('AGENTS.md'),
      '.gitignore 中排除了本地 AI 规范文件 AGENTS.md');
  expect(gitignoreContent.contains('PTX-plugins/'),
      '.gitignore 中排除了插件开发目录 PTX-plugins/');

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

  // 9. 插件商店: 远端目录契约、版本语义与安装编排约束
  print('\n--- 9. 插件商店目录契约与版本语义断言 ---');
  final storeEntryFile =
      File('packages/core/lib/src/store/plugin_store_entry.dart');
  expect(storeEntryFile.existsSync(), '插件商店条目模型 plugin_store_entry.dart 存在');
  final storeEntryCode = storeEntryFile.readAsStringSync();
  expect(
    storeEntryCode.contains('packageSizeBytes'),
    '商店条目携带 .ptx 体积信息 (安装前向用户展示)',
  );

  final storeClientFile =
      File('packages/core/lib/src/store/jsdelivr_plugin_store_source.dart');
  expect(storeClientFile.existsSync(),
      '插件商店目录客户端 jsdelivr_plugin_store_source.dart 存在');
  final storeClientCode = storeClientFile.readAsStringSync();
  expect(
    storeClientCode.contains('https://data.jsdelivr.com/v1'),
    '商店目录走 jsDelivr 文件清单接口 (一次请求返回整仓文件列表)',
  );
  expect(
    storeClientCode.contains('cdn.jsdelivr.net/gh'),
    '安装包按 jsDelivr CDN 地址下载',
  );
  expect(
    !storeClientCode.contains('api.github.com'),
    '不再依赖 GitHub Contents API: 未认证配额仅 60 次/小时, 一次刷新即会触顶',
  );
  expect(
    storeClientCode.contains('maxPackageBytes'),
    '客户端内置安装包体积上限校验',
  );
  expect(
    storeClientCode.contains('过于频繁'),
    '限流场景给出可展示的中文提示而非静默失败',
  );
  expect(
    storeClientCode.contains('_manifestCache') &&
        storeClientCode.contains('preferences'),
    '按内容哈希缓存插件清单, 源码未变化的插件刷新时不再重复下载',
  );

  final storeInspectionFile =
      File('packages/core/lib/src/store/plugin_package_inspection.dart');
  expect(storeInspectionFile.existsSync(), '安装包契约核对 inspectPluginPackage 存在');
  expect(
    storeInspectionFile.readAsStringSync().contains('missingEntryScript'),
    '安装前核对包内清单与入口脚本/UI 描述是否齐备',
  );

  // 版本比较语义: 直接断言生产实现
  expectEq(
    PluginStoreSemantics.compareVersions('1.2.3', '1.2.3'),
    0,
    '版本号相同时比较结果为 0',
  );
  expect(
    PluginStoreSemantics.compareVersions('1.2.4', '1.2.3') > 0,
    '补丁号更高判定为更新',
  );
  expect(
    PluginStoreSemantics.compareVersions('1.2.3', '1.3.0') < 0,
    '次版本更高判定为落后',
  );
  expectEq(
    PluginStoreSemantics.compareVersions('1.2', '1.2.0'),
    0,
    '缺失版本段补零 (1.2 等价 1.2.0)',
  );
  expectEq(
    PluginStoreSemantics.compareVersions('v1.2.0', '1.2.0'),
    0,
    '允许 v 前缀的版本写法',
  );
  expectEq(
    PluginStoreSemantics.compareVersions('1.2.0+3', '1.2.0'),
    0,
    '剥离构建号后再比较',
  );
  expectEq(
    PluginStoreSemantics.compareVersions('1a.2.3', '0.2.3'),
    0,
    '非数字版本段归零而非解析出脏数据',
  );
  expectEq(
    PluginStoreSemantics.compareVersions('not-a-version', '0.0.1'),
    -1,
    '完全无法解析的版本号按 0.0.0 处理',
  );
  expect(
    PluginStoreSemantics.isUpdateAvailable('1.1.0', '1.0.0'),
    '商店版本更高时提示可更新',
  );
  expect(
    !PluginStoreSemantics.isUpdateAvailable('1.0.0', '1.1.0'),
    '本地版本更高时不提示降级更新',
  );
  expect(
    PluginStoreSemantics.meetsMinAppVersion('0.1.0', null),
    '插件未声明 minAppVersion 时放行',
  );
  expect(
    !PluginStoreSemantics.meetsMinAppVersion('0.1.0', '0.2.0'),
    '宿主版本低于插件要求时拦截安装',
  );

  // 商店安装编排: 临时产物清理与注册时机
  final storeServiceFile = File('app/lib/src/plugin_store/store_service.dart');
  expect(storeServiceFile.existsSync(), '商店安装编排服务 store_service.dart 存在');
  final storeServiceCode = storeServiceFile.readAsStringSync();
  expect(
    storeServiceCode.contains('file.deleteSync()'),
    '安装结束后无条件清理临时安装包',
  );
  expect(
    storeServiceCode.contains('PluginInstaller.installFromPtx'),
    '商店安装复用统一的生产安装器 (校验与沙箱解压同一链路)',
  );

  final storeProvidersFile =
      File('app/lib/src/plugin_store/store_providers.dart');
  expect(storeProvidersFile.existsSync(), '商店依赖装配 store_providers.dart 存在');
  final storeProvidersCode = storeProvidersFile.readAsStringSync();
  expect(
    storeProvidersCode.contains("'Aclguh'") &&
        storeProvidersCode.contains("'PTX-plugins'"),
    '商店默认指向 Aclguh/PTX-plugins 插件仓库',
  );

  final storePageFile = File('app/lib/src/plugin_store/plugin_store_page.dart');
  expect(storePageFile.existsSync(), '插件商店页面 plugin_store_page.dart 存在');
  final storePageCode = storePageFile.readAsStringSync();
  expect(
    storePageCode.contains('plugin-source 清单'),
    '商店页向用户说明版本信息取自 plugin-source 清单',
  );
  expect(
    storePageCode.contains('已是最新') && storePageCode.contains('更新'),
    '商店页区分"安装 / 更新 / 已是最新"三种安装态',
  );
  expect(
    storePageCode.contains('正在下载并安装'),
    '安装期间提供进度遮罩并阻断重复触发',
  );
  expect(
    File('app/test/plugin_store_page_test.dart').existsSync(),
    '商店页具备宿主 Widget 测试',
  );
  expect(
    File('packages/core/test/plugin_store_test.dart').existsSync(),
    '商店客户端具备核心层单元测试',
  );

  // 10. README 测试用例数声明与真实测试规模同步校验
  print('\n--- 10. README 测试用例数声明与真实统计同步 ---');
  // 统计口径: 各模块 test/ 目录 *_test.dart 中 test( / testWidgets( 出现次数
  // (词边界匹配, testWidgets( 不会被 test( 重复计数)
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
  print('    实际统计: $breakdown, 共 $totalCases 用例');

  final readmeFile = File('README.md');
  expect(readmeFile.existsSync(), 'README.md 存在');

  if (args.contains('--sync-readme') && readmeFile.existsSync()) {
    final totalRegex = RegExp(r'共\s*\d+\s*用例');
    final breakdownRegex = RegExp(
      r'packages/core\s+\d+\s*/\s*packages/lua\s+\d+\s*/\s*packages/dui\s+\d+\s*/\s*packages/ui\s+\d+\s*/\s*app\s+\d+',
    );
    final newTotalStr = '共 $totalCases 用例';
    final newBreakdownStr =
        'packages/core ${perModuleCases['packages/core']} / packages/lua ${perModuleCases['packages/lua']} / packages/dui ${perModuleCases['packages/dui']} / packages/ui ${perModuleCases['packages/ui']} / app ${perModuleCases['app']}';
    var content = readmeFile.readAsStringSync();
    content = content.replaceFirst(totalRegex, newTotalStr);
    content = content.replaceFirst(breakdownRegex, newBreakdownStr);
    readmeFile.writeAsStringSync(content, flush: true);
    print('    [--sync-readme] 已自动同步更新 README.md 测试用例统计声明');
  }

  final readmeContent = readmeFile.readAsStringSync();

  final declaredTotal = RegExp(r'共\s*(\d+)\s*用例').firstMatch(readmeContent);
  expect(declaredTotal != null, 'README.md 声明了测试用例总数 (共 N 用例)');
  if (declaredTotal != null) {
    expect(
      int.parse(declaredTotal.group(1)!) == totalCases,
      'README 声明用例总数与 test/testWidgets 真实统计一致',
      'README 声明 ${declaredTotal.group(1)}, 实际统计 $totalCases ($breakdown)',
    );
  }

  final declaredBreakdown = RegExp(
    r'packages/core\s+(\d+)\s*/\s*packages/lua\s+(\d+)\s*/\s*packages/dui\s+(\d+)\s*/\s*packages/ui\s+(\d+)\s*/\s*app\s+(\d+)',
  ).firstMatch(readmeContent);
  expect(declaredBreakdown != null, 'README.md 声明了分模块用例数明细');
  if (declaredBreakdown != null) {
    for (var i = 0; i < modules.length; i++) {
      expect(
        int.parse(declaredBreakdown.group(i + 1)!) ==
            perModuleCases[modules[i]],
        'README 分模块用例数与真实统计一致 (${modules[i]})',
        'README 声明 ${declaredBreakdown.group(i + 1)}, 实际统计 ${perModuleCases[modules[i]]}',
      );
    }
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
