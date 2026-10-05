import 'dart:io';

import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';
import 'lua_engine.dart';

class LuaPluginRunner {
  final DynamicPlugin plugin;
  final LuaHostDelegate delegate;
  late final LuaEngine _engine;

  LuaPluginRunner({
    required this.plugin,
    required this.delegate,
  }) {
    // 只允许使用宿主 PluginRegistry 初始化时注入的上下文：
    // 自行构造默认上下文会绕过宿主权限管理与统一事件总线。
    final ctx = plugin.context;
    if (ctx == null) {
      throw StateError(
        '插件 [${plugin.id}] 尚未通过 PluginRegistry 完成初始化，拒绝启动 Lua 运行时',
      );
    }

    _engine = LuaEngine(
      context: ctx,
      delegate: delegate,
    );
  }

  Future<void> start() async {
    final entryFile = plugin.entryScriptFile;
    if (!await entryFile.exists()) {
      throw FileSystemException('入口 Lua 文件不存在', entryFile.path);
    }
    final content = await entryFile.readAsString();
    _engine.loadAndExecute(content);
    _engine.callFunction('onInit');
  }

  void dispatchAction(String functionName, [List<dynamic> args = const []]) {
    _engine.callFunction(functionName, args);
  }

  void onResume() {
    try {
      _engine.callFunction('onResume');
    } catch (_) {}
  }

  void onPause() {
    try {
      _engine.callFunction('onPause');
    } catch (_) {}
  }

  void dispose() {
    try {
      _engine.callFunction('onDispose');
    } catch (_) {}
    try {
      _engine.callFunction('onDestroy');
    } catch (_) {}
    _engine.close();
  }
}
