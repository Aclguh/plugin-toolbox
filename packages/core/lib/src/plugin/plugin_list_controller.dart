/// 插件排序列表控制器。
///
/// 独立维护"有序插件 ID 列表"的加载、增删与重排算法（含主界面网格与
/// 插件管理中心两处双向排序的一致性语义），使 [PluginRegistry] 可以专注
/// 于插件生命周期与启禁用状态机，不再混合列表排列细节。
class PluginListController {
  final List<String> _order = [];

  /// 当前排序（只读视图）
  List<String> get order => List.unmodifiable(_order);

  /// 载入持久化的排序，忽略未知 ID；未覆盖的已知插件按注册顺序追加在尾部
  void loadOrder(Set<String> knownIds, List<String> savedOrder) {
    _order.clear();
    for (final id in savedOrder) {
      if (knownIds.contains(id) && !_order.contains(id)) {
        _order.add(id);
      }
    }
    for (final id in knownIds) {
      if (!_order.contains(id)) {
        _order.add(id);
      }
    }
  }

  /// 新注册插件追加到列表尾部
  void add(String id) {
    if (!_order.contains(id)) {
      _order.add(id);
    }
  }

  /// 移除插件
  void remove(String id) {
    _order.remove(id);
  }

  /// 全量列表重排（插件管理中心）
  void reorder(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _order.length) return;
    if (newIndex < 0 || newIndex >= _order.length) return;
    if (oldIndex == newIndex) return;
    final item = _order.removeAt(oldIndex);
    _order.insert(newIndex, item);
  }

  /// 仅在启用子集内重排（主界面网格），保持禁用插件的相对位置不变。
  ///
  /// [enabledIds] 必须是当前启用插件按展示顺序组成的 ID 列表。
  void reorderEnabled(List<String> enabledIds, int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= enabledIds.length) return;
    if (newIndex < 0 || newIndex >= enabledIds.length) return;
    if (oldIndex == newIndex) return;

    final movingId = enabledIds[oldIndex];
    final targetId = enabledIds[newIndex];

    _order.remove(movingId);
    final targetPos = _order.indexOf(targetId);
    if (targetPos == -1) {
      _order.add(movingId);
    } else if (oldIndex < newIndex) {
      _order.insert(targetPos + 1, movingId);
    } else {
      _order.insert(targetPos, movingId);
    }
  }
}
