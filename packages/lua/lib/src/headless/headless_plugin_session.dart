import 'dart:async';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';
import '../delegates/domain_delegates.dart';
import '../lua_plugin_runner.dart';

/// 无头后台插件运行会话 (Headless Plugin Session)
///
/// 负责在无前台 UI 容器挂载的情况下，启动 Lua 虚拟机执行插件后台业务（如响应跨插件 IPC 服务调用）。
/// 内置空闲超时自动回收销毁机制。
class HeadlessPluginSession {
  final DynamicPlugin plugin;
  final HeadlessLuaHostDelegate delegate;
  final Duration idleTimeout;
  final void Function(String pluginId)? onTimeout;
  late final LuaPluginRunner runner;

  Timer? _idleTimer;
  bool _isDisposed = false;

  HeadlessPluginSession({
    required this.plugin,
    HeadlessLuaHostDelegate? delegate,
    this.idleTimeout = const Duration(seconds: 30),
    this.onTimeout,
  }) : delegate = delegate ?? HeadlessLuaHostDelegate() {
    runner = LuaPluginRunner(
      plugin: plugin,
      delegate: this.delegate,
    );
  }

  bool get isDisposed => _isDisposed;

  /// 启动无头后台会话
  Future<void> start() async {
    if (_isDisposed) throw StateError('会话已销毁');
    await runner.start();
    _resetIdleTimer();
  }

  /// 触发生命周期保活（在跨插件收到请求时调用）
  void touch() {
    if (_isDisposed) return;
    _resetIdleTimer();
  }

  void _resetIdleTimer() {
    _idleTimer?.cancel();
    if (idleTimeout > Duration.zero) {
      _idleTimer = Timer(idleTimeout, () {
        dispose();
        onTimeout?.call(plugin.id);
      });
    }
  }

  /// 销毁并释放无头会话及虚拟机资源
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _idleTimer?.cancel();
    _idleTimer = null;
    PluginIpcBroker.instance.unregisterService(plugin.id);
    runner.dispose();
  }
}

/// 无头后台插件会话管理器
class HeadlessPluginSessionManager {
  final Map<String, HeadlessPluginSession> _sessions = {};
  final Duration defaultIdleTimeout;

  HeadlessPluginSessionManager({
    this.defaultIdleTimeout = const Duration(seconds: 30),
  });

  /// 获取或拉起目标插件的无头会话
  Future<HeadlessPluginSession> getOrLaunch(
    DynamicPlugin plugin, {
    HeadlessLuaHostDelegate? delegate,
    Duration? idleTimeout,
  }) async {
    final existing = _sessions[plugin.id];
    if (existing != null && !existing.isDisposed) {
      existing.touch();
      return existing;
    }

    final session = HeadlessPluginSession(
      plugin: plugin,
      delegate: delegate,
      idleTimeout: idleTimeout ?? defaultIdleTimeout,
      onTimeout: (id) => _sessions.remove(id),
    );
    _sessions[plugin.id] = session;
    await session.start();
    return session;
  }

  /// 查询指定插件是否处于活跃的无头会话中
  bool isSessionActive(String pluginId) {
    final session = _sessions[pluginId];
    return session != null && !session.isDisposed;
  }

  /// 获取指定活跃会话
  HeadlessPluginSession? getSession(String pluginId) {
    final session = _sessions[pluginId];
    if (session != null && !session.isDisposed) {
      return session;
    }
    return null;
  }

  /// 手动关闭指定插件的无头会话
  void closeSession(String pluginId) {
    final session = _sessions.remove(pluginId);
    session?.dispose();
  }

  /// 关闭并清理所有无头会话
  void closeAll() {
    for (final session in _sessions.values) {
      session.dispose();
    }
    _sessions.clear();
  }
}
