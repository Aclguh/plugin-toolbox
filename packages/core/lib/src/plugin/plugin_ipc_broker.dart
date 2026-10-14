import 'dart:async';

/// 跨插件互通与服务调用经纪人 (Inter-Plugin Communication Broker)
///
/// 维护各插件注册暴露的公共服务接口，协调插件间的异步 RPC 调用与管道传值，
/// 严格限定于内存中已加载/已启用的插件上下文，隔离非法的跨插件越权访问。
class _ServiceEntry {
  final Future<dynamic> Function(dynamic args) handler;
  final Set<String>? allowedCallers;

  _ServiceEntry({required this.handler, this.allowedCallers});
}

/// 跨插件互通与服务调用经纪人 (Inter-Plugin Communication Broker)
///
/// 维护各插件注册暴露的公共服务接口，协调插件间的异步 RPC 调用与管道传值，
/// 严格限定于内存中已加载/已启用的插件上下文，隔离非法的跨插件越权访问。
class PluginIpcBroker {
  PluginIpcBroker();

  /// 默认共享经纪人实例（支持依赖注入与测试替换）
  static PluginIpcBroker instance = PluginIpcBroker();

  static const Duration defaultTimeout = Duration(seconds: 5);
  static const int defaultMaxCallsPerSecond = 50;

  final Map<String, _ServiceEntry> _services = {};
  final Map<String, List<DateTime>> _callTimestamps = {};

  /// 注册插件提供的公共服务接口。
  /// 可选指定 [allowedCallers] 白名单集合；为 null 或包含 '*' 表示对所有插件公开。
  void registerService(
    String pluginId,
    String functionName,
    Future<dynamic> Function(dynamic args) handler, {
    Set<String>? allowedCallers,
  }) {
    _services['$pluginId:$functionName'] = _ServiceEntry(
      handler: handler,
      allowedCallers: allowedCallers,
    );
  }

  /// 注销指定插件的所有或特定接口
  void unregisterService(String pluginId, [String? functionName]) {
    if (functionName != null) {
      _services.remove('$pluginId:$functionName');
    } else {
      _services.removeWhere((key, _) => key.startsWith('$pluginId:'));
    }
  }

  /// 查询指定服务是否已就绪
  bool hasService(String pluginId, String functionName) {
    return _services.containsKey('$pluginId:$functionName');
  }

  /// 查询指定服务是否允许 [callerPluginId] 调用
  bool isCallerAllowed(
    String targetPluginId,
    String functionName,
    String callerPluginId,
  ) {
    final entry = _services['$targetPluginId:$functionName'];
    if (entry == null) return false;
    final allowed = entry.allowedCallers;
    if (allowed == null || allowed.isEmpty || allowed.contains('*')) {
      return true;
    }
    return allowed.contains(callerPluginId);
  }

  /// 调用目标插件暴露的接口。
  /// 支持 [timeout] 熔断中断（默认 5 秒）与基于滑动窗口的 [maxCallsPerSecond] 频次限制（默认 50 次/秒）。
  Future<Map<String, dynamic>> call({
    required String callerPluginId,
    required String targetPluginId,
    required String functionName,
    dynamic args,
    Duration timeout = defaultTimeout,
    int maxCallsPerSecond = defaultMaxCallsPerSecond,
  }) async {
    final key = '$targetPluginId:$functionName';
    final entry = _services[key];
    if (entry == null) {
      return {
        'ok': false,
        'error': '目标插件 [$targetPluginId] 未暴露接口 [$functionName]',
      };
    }

    if (!isCallerAllowed(targetPluginId, functionName, callerPluginId)) {
      return {
        'ok': false,
        'error':
            '跨插件访问拒绝: 目标插件 [$targetPluginId] 未向 [$callerPluginId] 授权接口 [$functionName]',
      };
    }

    if (maxCallsPerSecond > 0) {
      final rateLimitKey = '$callerPluginId->$key';
      final now = DateTime.now();
      final windowStart = now.subtract(const Duration(seconds: 1));
      final timestamps = _callTimestamps.putIfAbsent(rateLimitKey, () => []);
      timestamps.removeWhere((t) => t.isBefore(windowStart));
      if (timestamps.length >= maxCallsPerSecond) {
        return {
          'ok': false,
          'code': 'IPC_RATE_LIMITED',
          'error':
              '调用频次超限: 插件 [$callerPluginId] 调用 [$key] 超过每秒 $maxCallsPerSecond 次限制',
        };
      }
      timestamps.add(now);
    }

    try {
      final res = await entry.handler(args).timeout(timeout, onTimeout: () {
        throw TimeoutException('跨插件调用 [$key] 超时 (${timeout.inSeconds}秒)');
      });
      return {'ok': true, 'result': res};
    } on TimeoutException catch (e) {
      return {
        'ok': false,
        'code': 'IPC_TIMEOUT',
        'error': e.message ?? '跨插件调用超时',
      };
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }

  /// 清空所有注册的服务与限流状态（供测试与生命周期重置使用）
  void reset() {
    _services.clear();
    _callTimestamps.clear();
  }
}
