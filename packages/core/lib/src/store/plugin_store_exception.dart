/// 商店操作失败时抛出的领域异常：携带可直接展示给用户的中文说明。
class PluginStoreException implements Exception {
  const PluginStoreException(this.message);

  /// 面向用户的中文错误描述
  final String message;

  @override
  String toString() => message;
}

/// 远端资源不存在（仓库、目录或某个 .ptx 缺失）。
///
/// 单独成类是为了让"可选项缺失"能被精确捕获，而不必比较错误文案。
class PluginStoreNotFoundException extends PluginStoreException {
  const PluginStoreNotFoundException(super.message);
}
