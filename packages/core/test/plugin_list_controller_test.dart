import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// PluginListController 的直接单元测试。
///
/// 控制器本身不触碰持久化（保持纯内存算法，便于独立验证）；持久化由宿主
/// 装配层以 `plugin_toolbox_plugin_order` 键读写 SharedPreferences 完成。
/// 本文件同时验证该跨层契约：控制器的 order 输出经宿主键存取后可被
/// loadOrder 无损还原，且损坏数据不会导致崩溃。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const orderKey = 'plugin_toolbox_plugin_order';

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('loadOrder 载入语义', () {
    test('未知 ID 被忽略，未覆盖的已知插件按注册顺序追加尾部', () {
      final controller = PluginListController();
      controller.loadOrder(
        {'a', 'b', 'c', 'd'},
        ['c', 'ghost', 'a'], // ghost 未注册，应被忽略
      );
      expect(controller.order, ['c', 'a', 'b', 'd']);
    });

    test('持久化列表中的重复 ID 被去重', () {
      final controller = PluginListController();
      controller.loadOrder({'a', 'b'}, ['a', 'a', 'b', 'a']);
      expect(controller.order, ['a', 'b']);
    });

    test('空存档时按注册顺序排列', () {
      final controller = PluginListController();
      controller.loadOrder({'x', 'y', 'z'}, const []);
      expect(controller.order, ['x', 'y', 'z']);
    });

    test('重复载入会重置而非累加', () {
      final controller = PluginListController();
      controller.loadOrder({'a', 'b'}, ['b', 'a']);
      controller.loadOrder({'a', 'b', 'c'}, ['a']);
      expect(controller.order, ['a', 'b', 'c']);
    });
  });

  group('add / remove', () {
    test('add 追加尾部且幂等', () {
      final controller = PluginListController();
      controller.add('a');
      controller.add('b');
      controller.add('a');
      expect(controller.order, ['a', 'b']);
    });

    test('remove 移除存在项，忽略不存在项', () {
      final controller = PluginListController();
      controller.loadOrder({'a', 'b', 'c'}, const []);
      controller.remove('b');
      controller.remove('ghost');
      expect(controller.order, ['a', 'c']);
    });

    test('order 返回只读视图，外部修改不影响内部状态', () {
      final controller = PluginListController();
      controller.add('a');
      expect(() => controller.order.add('b'), throwsUnsupportedError);
      expect(controller.order, ['a']);
    });
  });

  group('reorder 全量重排（插件管理中心）', () {
    test('前移与后移语义正确', () {
      final controller = PluginListController();
      controller.loadOrder({'a', 'b', 'c', 'd'}, const []);

      controller.reorder(0, 2); // a 移到 c 的位置
      expect(controller.order, ['b', 'c', 'a', 'd']);

      controller.reorder(3, 0); // d 移到最前
      expect(controller.order, ['d', 'b', 'c', 'a']);
    });

    test('越界、负索引与相同索引均被安全忽略', () {
      final controller = PluginListController();
      controller.loadOrder({'a', 'b', 'c'}, const []);

      controller.reorder(-1, 1);
      controller.reorder(1, -1);
      controller.reorder(3, 0);
      controller.reorder(0, 3);
      controller.reorder(1, 1);
      expect(controller.order, ['a', 'b', 'c']);
    });

    test('空列表上调用不抛异常', () {
      final controller = PluginListController();
      controller.reorder(0, 0);
      expect(controller.order, isEmpty);
    });
  });

  group('reorderEnabled 启用子集重排（主界面网格）', () {
    test('子集内后移：插入到目标启用项之后，禁用项位置不动', () {
      final controller = PluginListController();
      controller.loadOrder({'a', 'b', 'c', 'd', 'e'}, const []);
      // 启用: a, c, e；禁用: b, d
      controller.reorderEnabled(['a', 'c', 'e'], 0, 1); // a 移到 c 之后
      expect(controller.order, ['b', 'c', 'a', 'd', 'e']);
    });

    test('子集内前移：插入到目标启用项之前', () {
      final controller = PluginListController();
      controller.loadOrder({'a', 'b', 'c', 'd', 'e'}, const []);
      controller.reorderEnabled(['a', 'c', 'e'], 2, 0); // e 移到 a 之前
      expect(controller.order, ['e', 'a', 'b', 'c', 'd']);
    });

    test('移动项被移除后目标项不在总表时追加尾部（容错降级）', () {
      final controller = PluginListController();
      controller.loadOrder({'a', 'b', 'c'}, const []);
      // enabledIds 包含未注册的 ghost：movingId 有效但 targetId 不在总表
      controller.reorderEnabled(['a', 'ghost'], 0, 1);
      expect(controller.order, ['b', 'c', 'a']);
    });

    test('越界、负索引与相同索引均被安全忽略', () {
      final controller = PluginListController();
      controller.loadOrder({'a', 'b', 'c'}, const []);
      controller.reorderEnabled(['a', 'b'], -1, 1);
      controller.reorderEnabled(['a', 'b'], 0, 2);
      controller.reorderEnabled(['a', 'b'], 1, 1);
      expect(controller.order, ['a', 'b', 'c']);
    });
  });

  group('双向排序一致性（主界面网格 <-> 插件管理中心）', () {
    test('两处交替重排后顺序与逐步推演一致', () {
      final controller = PluginListController();
      controller.loadOrder({'a', 'b', 'c', 'd', 'e'}, const []);
      // 初始: a b c d e；禁用: b, d -> 启用展示: a c e

      // 主界面网格: 把 e 拖到最前 (enabled 内 2 -> 0)
      controller.reorderEnabled(['a', 'c', 'e'], 2, 0);
      expect(controller.order, ['e', 'a', 'b', 'c', 'd']);

      // 插件管理中心（全量列表）: 把 d 拖到第 1 位 (全量内 4 -> 1)
      controller.reorder(4, 1);
      expect(controller.order, ['e', 'd', 'a', 'b', 'c']);

      // 主界面网格再次拖动（禁用项不变，启用展示现为: e a c）
      controller.reorderEnabled(['e', 'a', 'c'], 0, 2);
      expect(controller.order, ['d', 'a', 'b', 'c', 'e']);

      // 双向一致性判定：启用子集在总表中的相对顺序，必须等于
      // 主界面网格最后一次展示的相对顺序
      final enabledDisplay = ['a', 'c', 'e'];
      final enabledInOrder =
          controller.order.where(enabledDisplay.contains).toList();
      expect(enabledInOrder, ['a', 'c', 'e']);
    });

    test('网格拖动不穿越禁用项的相对位置', () {
      final controller = PluginListController();
      controller.loadOrder({'a', 'b', 'c', 'd'}, const []);
      // 禁用: b（固定在 a 与 c 之间）；启用展示: a c d
      controller.reorderEnabled(['a', 'c', 'd'], 0, 2); // a 移到最后
      // b 的相对位置保持：仍在 c 之前
      expect(controller.order.indexOf('b'),
          lessThan(controller.order.indexOf('c')));
      expect(controller.order, ['b', 'c', 'd', 'a']);
    });
  });

  group('持久化契约（SharedPreferences 键 plugin_toolbox_plugin_order）', () {
    test('排序经宿主键保存后可被无损还原', () async {
      final prefs = await SharedPreferences.getInstance();
      final controller = PluginListController();
      controller.loadOrder({'a', 'b', 'c', 'd'}, const []);
      controller.reorder(3, 0); // d a b c

      // 模拟宿主装配层保存排序
      await prefs.setStringList(orderKey, controller.order);

      // 模拟应用重启：新控制器从持久化存档恢复
      final restored = PluginListController();
      restored.loadOrder({'a', 'b', 'c', 'd'}, prefs.getStringList(orderKey)!);
      expect(restored.order, ['d', 'a', 'b', 'c']);
    });

    test('双向重排结果持久化后两处恢复顺序一致', () async {
      final prefs = await SharedPreferences.getInstance();
      final controller = PluginListController();
      controller.loadOrder({'a', 'b', 'c', 'd', 'e'}, const []);
      controller.reorderEnabled(['a', 'c', 'e'], 2, 0); // 网格: e 到最前
      controller.reorder(0, 3); // 管理中心: e 移到第 3 位

      await prefs.setStringList(orderKey, controller.order);

      final restored = PluginListController();
      restored
          .loadOrder({'a', 'b', 'c', 'd', 'e'}, prefs.getStringList(orderKey)!);
      expect(restored.order, controller.order,
          reason: '同一数据源两处变动实时同步，恢复后不得出现分叉');
    });

    test('存档缺失或包含已卸载插件时安全降级', () async {
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList(orderKey), isNull);

      // 存档含已卸载 ID：恢复时静默剔除，不崩溃
      await prefs.setStringList(orderKey, ['uninstalled', 'b', 'a']);
      final controller = PluginListController();
      controller.loadOrder({'a', 'b', 'c'}, prefs.getStringList(orderKey)!);
      expect(controller.order, ['b', 'a', 'c']);
    });

    test('重排与增删后内存状态独立完整，不依赖持久化成功', () async {
      // 不写入 prefs（模拟存储故障场景），控制器内存算法不受影响
      final controller = PluginListController();
      controller.loadOrder({'a', 'b', 'c'}, const []);
      controller.reorder(2, 0);
      controller.remove('b');
      controller.add('d');
      expect(controller.order, ['c', 'a', 'd']);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList(orderKey), isNull,
          reason: '控制器自身不产生持久化副作用，写盘职责在宿主装配层');
    });
  });
}
