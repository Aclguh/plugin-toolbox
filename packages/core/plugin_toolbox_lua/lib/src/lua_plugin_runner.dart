import 'dart:io';
import 'package:logger/logger.dart';
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
    final ctx = plugin.context ??
        PluginContext(
          pluginId: plugin.id,
          storage: PluginStorageImpl(namespace: plugin.id),
          eventBus: EventBusImpl(),
          logger: Logger(),
          grantedPermissions: plugin.manifest.permissions.toSet(),
        );

    _engine = LuaEngine(
      context: ctx,
      delegate: delegate,
    );
  }

  void start() {
    final entryFile = plugin.entryScriptFile;
    if (!entryFile.existsSync()) {
      throw FileSystemException('入口 Lua 文件不存在', entryFile.path);
    }
    final content = entryFile.readAsStringSync();
    _engine.loadAndExecute(content);
    _engine.callFunction('onInit');
  }

  void dispatchAction(String functionName, [List<dynamic> args = const []]) {
    _engine.callFunction(functionName, args);
  }

  void dispose() {
    try {
      _engine.callFunction('onDispose');
    } catch (_) {}
    _engine.close();
  }
}
