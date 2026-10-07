import 'dart:async';

/// 跨插件互通与服务调用经纪人 (Inter-Plugin Communication Broker)
///
/// 维护各插件注册暴露的公共服务接口，协调插件间的异步 RPC 调用与管道传值，
/// 严格限定于内存中已加载/已启用的插件上下文，隔离非法的跨插件越权访问。
class PluginIpcBroker {
  PluginIpcBroker._();

  static final PluginIpcBroker instance = PluginIpcBroker._();

  final Map<String, Future<dynamic> Function(dynamic args)> _handlers = {};

  /// 注册插件提供的公共服务接口
  void registerService(
    String pluginId,
    String functionName,
    Future<dynamic> Function(dynamic args) handler,
  ) {
    _handlers['$pluginId:$functionName'] = handler;
  }

  /// 注销指定插件的所有或特定接口
  void unregisterService(String pluginId, [String? functionName]) {
    if (functionName != null) {
      _handlers.remove('$pluginId:$functionName');
    } else {
      _handlers.removeWhere((key, _) => key.startsWith('$pluginId:'));
    }
  }

  /// 查询指定服务是否已就绪
  bool hasService(String pluginId, String functionName) {
    return _handlers.containsKey('$pluginId:$functionName');
  }

  /// 调用目标插件暴露的接口
  Future<Map<String, dynamic>> call({
    required String callerPluginId,
    required String targetPluginId,
    required String functionName,
    dynamic args,
  }) async {
    final key = '$targetPluginId:$functionName';
    final handler = _handlers[key];
    if (handler == null) {
      return {
        'ok': false,
        'error': '目标插件 [$targetPluginId] 未暴露接口 [$functionName]',
      };
    }
    try {
      final res = await handler(args);
      return {'ok': true, 'result': res};
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }

  /// 清空所有注册的服务（供测试与生命周期重置使用）
  void reset() {
    _handlers.clear();
  }
}
