import 'dart:async';
import 'package:logger/logger.dart';
import 'app_event.dart';

/// 全局事件总线契约
abstract class EventBus {
  /// 分发事件
  void fire(AppEvent event);

  /// 监听特定类型的事件流
  Stream<T> on<T extends AppEvent>();

  /// 释放事件总线资源
  void dispose();
}

/// 具备错误隔离与防事件风暴背压控制的事件总线实现
class EventBusImpl implements EventBus {
  static final Logger _defaultLogger = Logger(
    printer: PrettyPrinter(methodCount: 0, lineLength: 80),
  );

  final StreamController<AppEvent> _controller;
  final Logger _logger;
  final int maxQueueDepth;
  int _pendingCount = 0;

  EventBusImpl({
    this.maxQueueDepth = 1000,
    Logger? logger,
  })  : _logger = logger ?? _defaultLogger,
        _controller = StreamController<AppEvent>.broadcast(sync: false);

  @override
  void fire(AppEvent event) {
    if (_controller.isClosed) {
      _logger.w('尝试向已关闭的 EventBus 发送事件: $event');
      return;
    }

    if (_pendingCount >= maxQueueDepth) {
      _logger.w('EventBus 触发背压深度阈值 ($maxQueueDepth)，丢弃超限事件以防事件风暴: $event');
      return;
    }

    _pendingCount++;
    try {
      _controller.add(event);
    } catch (e, st) {
      _logger.e('EventBus 分发事件异常: $event', error: e, stackTrace: st);
    } finally {
      scheduleMicrotask(() {
        if (_pendingCount > 0) _pendingCount--;
      });
    }
  }

  @override
  Stream<T> on<T extends AppEvent>() {
    return _controller.stream
        .where((e) => e is T)
        .cast<T>()
        .handleError((error, stackTrace) {
          _logger.w('EventBus 监听流捕获内部异常: $error', stackTrace: stackTrace);
        });
  }

  @override
  void dispose() {
    if (!_controller.isClosed) {
      _controller.close();
    }
  }
}
