/// 插件远端仓库坐标配置与解析工具。
///
/// 支持用户自定义 GitHub 插件仓库（例如团队私有或第三方插件源），
/// 默认指向官方插件开发仓库 Aclguh/PTX-plugins。
class PluginRepositoryConfig {
  const PluginRepositoryConfig({
    required this.owner,
    required this.repository,
    this.customUrl,
  });

  /// 官方默认仓库拥有者
  static const String defaultOwner = 'Aclguh';

  /// 官方默认仓库名称
  static const String defaultRepository = 'PTX-plugins';

  /// 官方默认仓库 GitHub 主页地址
  static const String defaultUrl =
      'https://github.com/$defaultOwner/$defaultRepository';

  /// 默认仓库配置单例
  static const PluginRepositoryConfig defaultConfig = PluginRepositoryConfig(
    owner: defaultOwner,
    repository: defaultRepository,
    customUrl: defaultUrl,
  );

  /// 仓库拥有者（GitHub 用户名或组织名）
  final String owner;

  /// 仓库名
  final String repository;

  /// 用户输入的原始 URL 或地址（若为自定义输入）
  final String? customUrl;

  /// 是否为官方默认仓库
  bool get isDefault =>
      owner.toLowerCase() == defaultOwner.toLowerCase() &&
      repository.toLowerCase() == defaultRepository.toLowerCase();

  /// 规范化的 GitHub 仓库地址
  String get githubUrl => 'https://github.com/$owner/$repository';

  /// 简短坐标展示（形如 `owner/repository`）
  String get summary => '$owner/$repository';

  /// 验证 GitHub 用户名/组织名是否合法
  static bool isValidGithubOwner(String name) {
    if (name.isEmpty || name.length > 39) return false;
    if (name == '.' || name == '..') return false;
    if (name.startsWith('-') || name.endsWith('-')) return false;
    return RegExp(r'^[a-zA-Z0-9_\-\.]+$').hasMatch(name);
  }

  /// 验证 GitHub 仓库名是否合法
  static bool isValidGithubRepo(String name) {
    if (name.isEmpty || name.length > 100) return false;
    if (name == '.' || name == '..') return false;
    // GitHub 仓库名仅允许字母、数字、中划线、下划线与点
    return RegExp(r'^[a-zA-Z0-9_\-\.]+$').hasMatch(name);
  }

  /// 解析用户输入的 GitHub 仓库地址或简写。
  ///
  /// 支持格式：
  /// - `https://github.com/owner/repo`
  /// - `http://github.com/owner/repo`
  /// - `github.com/owner/repo`
  /// - `owner/repo`
  /// - 末尾可选斜杠 `/` 或 `.git`
  ///
  /// 若格式不合法或含有非法字符则返回 `null`。
  static PluginRepositoryConfig? tryParse(String? input) {
    if (input == null) return null;
    var trimmed = input.trim();
    if (trimmed.isEmpty) return null;

    // 去除末尾的斜杠
    while (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1).trim();
    }
    if (trimmed.isEmpty) return null;

    // 去除末尾的 .git
    if (trimmed.endsWith('.git')) {
      trimmed = trimmed.substring(0, trimmed.length - 4).trim();
    }
    if (trimmed.isEmpty) return null;

    // 情况 1: 带有 URL 前缀
    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.hasScheme) {
      final host = uri.host.toLowerCase();
      if (host == 'github.com' || host == 'www.github.com') {
        final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
        if (segments.length >= 2) {
          final owner = segments[0];
          var repo = segments[1];
          if (repo.endsWith('.git')) {
            repo = repo.substring(0, repo.length - 4);
          }
          if (isValidGithubOwner(owner) && isValidGithubRepo(repo)) {
            return PluginRepositoryConfig(
              owner: owner,
              repository: repo,
              customUrl: input.trim(),
            );
          }
        }
      }
      return null;
    }

    // 情况 2: github.com/owner/repo 无 scheme
    if (trimmed.toLowerCase().startsWith('github.com/')) {
      final sub = trimmed.substring('github.com/'.length);
      final parts = sub.split('/').where((s) => s.isNotEmpty).toList();
      if (parts.length == 2) {
        final owner = parts[0];
        final repo = parts[1];
        if (isValidGithubOwner(owner) && isValidGithubRepo(repo)) {
          return PluginRepositoryConfig(
            owner: owner,
            repository: repo,
            customUrl: input.trim(),
          );
        }
      }
      return null;
    }

    // 情况 3: owner/repo 格式
    final parts = trimmed.split('/');
    if (parts.length == 2) {
      final owner = parts[0].trim();
      final repo = parts[1].trim();
      if (isValidGithubOwner(owner) && isValidGithubRepo(repo)) {
        return PluginRepositoryConfig(
          owner: owner,
          repository: repo,
          customUrl: input.trim(),
        );
      }
    }

    return null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PluginRepositoryConfig &&
          runtimeType == other.runtimeType &&
          owner.toLowerCase() == other.owner.toLowerCase() &&
          repository.toLowerCase() == other.repository.toLowerCase();

  @override
  int get hashCode =>
      owner.toLowerCase().hashCode ^ repository.toLowerCase().hashCode;

  @override
  String toString() => 'PluginRepositoryConfig($summary)';
}
