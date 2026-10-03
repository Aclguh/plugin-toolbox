/// 插件分类枚举
enum PluginCategory {
  encoding('编解码', '编码与解码工具'),
  generator('生成工具', '生成各种内容'),
  text('文本处理', '文本与数据处理'),
  system('系统工具', '系统信息与诊断'),
  calculator('计算工具', '计算与转换'),
  network('网络工具', '网络与通信工具'),
  other('其他', '其他工具');

  const PluginCategory(this.label, this.description);

  final String label;
  final String description;

  static PluginCategory fromString(String? value) {
    if (value == null) return PluginCategory.other;
    return PluginCategory.values.firstWhere(
      (e) => e.name.toLowerCase() == value.toLowerCase(),
      orElse: () => PluginCategory.other,
    );
  }
}
