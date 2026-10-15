/// 可由 Lua 引擎集中托管释放的资源接口
abstract interface class LuaDisposable {
  void dispose();
}

/// 集中式资源生命周期追踪器。
///
/// 在 [LuaEngine.close] 调用时，以逆序安全隔离地清理所有托管的系统资源、
/// 硬件连接与原生通道，防止单个模块异常阻断其余模块的回收流程。
class DisposableTracker {
  final List<void Function()> _disposers = [];

  /// 注册 [LuaDisposable] 资源实例
  void add(LuaDisposable disposable) {
    _disposers.add(disposable.dispose);
  }

  /// 注册自定义清理回调闭包
  void addCallback(void Function() disposeFn) {
    _disposers.add(disposeFn);
  }

  /// 逆序安全释放所有托管资源
  void disposeAll() {
    for (final disposer in _disposers.reversed.toList()) {
      try {
        disposer();
      } catch (_) {
        // 异常隔离，防止单个组件抛错阻断其余资源释放
      }
    }
    _disposers.clear();
  }
}
