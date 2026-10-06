import '../model/plugin_manifest.dart';

/// 插件商店条目的本地安装态。
///
/// 商店把「远端目录（plugin-source 的 plugin.json）」与「本地已安装插件（沙箱
/// 内的 plugin.json）」做版本比对，只产出这三种互斥状态，界面据此决定按钮文案。
enum PluginStoreInstallState {
  /// 本地没有任何同 ID 插件
  notInstalled,

  /// 本地已安装且版本不低于商店版本
  upToDate,

  /// 本地已安装但版本低于商店版本（或本地版本号无法比较）
  updateAvailable,
}

/// 安装态在界面上的派生语义。
extension PluginStoreInstallStateX on PluginStoreInstallState {
  /// 是否需要向用户提供下载入口（未安装或可更新）
  bool get needsDownload => this != PluginStoreInstallState.upToDate;
}

/// 商店版本比较与安装态判定。
///
/// 刻意保持为纯函数集合：不依赖 Flutter、网络与文件系统，便于单元测试与
/// `tool/verify.dart` 直接用生产实现做断言。
abstract final class PluginStoreSemantics {
  /// 语义化版本比较：返回负数表示 [a] 早于 [b]，0 表示等价，正数表示 [a] 晚于 [b]。
  ///
  /// 只解析以点分隔的前三段数字段；`1.2.0+3`、`v1.2` 之类的常见写法均可解析，
  /// 缺失段补 0（`1.2` == `1.2.0`）。任何无法解析的版本号一律按 0 处理：
  /// 插件清单的版本号由第三方提供，格式不受宿主约束，绝不能因脏数据抛错崩溃。
  static int compareVersions(String a, String b) {
    final left = _parseVersion(a);
    final right = _parseVersion(b);
    for (int i = 0; i < 3; i++) {
      final diff = left[i] - right[i];
      if (diff != 0) return diff;
    }
    return 0;
  }

  /// 商店版本 [storeVersion] 是否比本地版本 [installedVersion] 更新
  static bool isUpdateAvailable(String storeVersion, String installedVersion) {
    return compareVersions(storeVersion, installedVersion) > 0;
  }

  /// 判定商店条目在本地安装态。
  ///
  /// [installedManifests] 为本地已安装插件的清单列表（由宿主扫描沙箱得到）；
  /// 只按 [pluginId] 匹配，未命中即为未安装。
  static PluginStoreInstallState resolveState({
    required String pluginId,
    required String storeVersion,
    required Iterable<PluginManifest> installedManifests,
  }) {
    for (final manifest in installedManifests) {
      if (manifest.id != pluginId) continue;
      return isUpdateAvailable(storeVersion, manifest.version)
          ? PluginStoreInstallState.updateAvailable
          : PluginStoreInstallState.upToDate;
    }
    return PluginStoreInstallState.notInstalled;
  }

  /// 宿主版本 [appVersion] 是否满足插件要求的 [minAppVersion]。
  ///
  /// 插件未声明最低版本要求时恒为 true；声明了但宿主解析不出数字时按不满足处理，
  /// 宁可让用户看到"需要更新宿主"的提示，也不要装上必然报错的插件。
  static bool meetsMinAppVersion(String appVersion, String? minAppVersion) {
    if (minAppVersion == null || minAppVersion.trim().isEmpty) return true;
    if (!_isNumericVersion(appVersion)) return false;
    return compareVersions(appVersion, minAppVersion) >= 0;
  }

  static List<int> _parseVersion(String source) {
    final trimmed = source.trim();
    final cleaned = trimmed.startsWith('v') || trimmed.startsWith('V')
        ? trimmed.substring(1)
        : trimmed;
    // 先剥离构建号（`+N`）与预发布标记（`-beta`），再按点分段
    final main = cleaned.split('+').first.split('-').first;
    final segments = main.split('.');
    final result = <int>[0, 0, 0];
    for (int i = 0; i < 3 && i < segments.length; i++) {
      // 整段必须全是数字：int.tryParse 会接受 `1a` 这类带尾随垃圾的输入并解析出 1,
      // 版本号来自第三方清单, 必须严格拒绝以保证脏数据一律归零
      final segment = segments[i].trim();
      result[i] = _digitsOnly.hasMatch(segment) ? int.parse(segment) : 0;
    }
    return result;
  }

  static final RegExp _digitsOnly = RegExp(r'^[0-9]+$');

  static bool _isNumericVersion(String source) {
    final trimmed = source.trim();
    if (trimmed.isEmpty) return false;
    final firstSegment =
        trimmed.split('.').first.replaceFirst(RegExp(r'^[vV]'), '').trim();
    return _digitsOnly.hasMatch(firstSegment);
  }
}
