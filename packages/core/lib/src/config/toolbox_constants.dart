/// PluginToolbox 全局安全策略、资源配额与虚拟机运行常量配置中枢
class ToolboxConstants {
  ToolboxConstants._();

  // --- 插件安装包与解压安全约束 ---
  /// 单个 .ptx 归档包文件体积上限 (10MB)
  static const int maxPackageSizeBytes = 10 * 1024 * 1024;

  /// 单个插件解压后总展开体积上限 (50MB)
  static const int maxUncompressedSizeBytes = 50 * 1024 * 1024;

  /// 压缩包膨胀比安全上限 (20倍)，防范 Zip Bomb
  static const int maxInflationRatio = 20;

  /// 膨胀比触发校验阈值 (5MB)
  static const int inflationCheckThresholdBytes = 5 * 1024 * 1024;

  /// 安装包内条目数上限 (1000个)
  static const int maxEntryCount = 1000;

  /// 默认单插件沙箱存储配额 (50MB)
  static const int defaultStorageQuotaMb = 50;

  // --- 网络请求安全与资源约束 ---
  /// 网络请求单阶段默认超时 (15000ms)
  static const int defaultNetworkTimeoutMs = 15000;

  /// 30x 重定向最大跟随跳数 (5跳)
  static const int maxRedirectHops = 5;

  /// 单次 HTTP 响应体最大读取字节上限 (10MB)
  static const int maxResponseBytes = 10 * 1024 * 1024;

  // --- Lua 虚拟机沙箱保护约束 ---
  /// 单次 Lua 执行允许的最大指令数 (5,000,000)
  static const int defaultInstructionBudget = 5000000;

  /// 单个 Lua 虚拟机实例允许的最大堆内存预算 (32MB)
  static const int defaultMemoryBudget = 32 * 1024 * 1024;
}
