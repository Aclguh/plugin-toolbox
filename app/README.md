# PluginToolbox App (Android 宿主壳工程)

本目录为 **PluginToolbox** 的主应用端工程（Flutter Application），负责协调多子包、组装系统路由、调度全局状态，并向用户提供原生的交互容器。

---

## 核心职责

1. **生命周期与环境初始化**：
   - 应用启动时扫描沙箱目录中已安装的 `.ptx` 动态插件。
   - 读取并还原持久化的插件排序配置（`plugin_toolbox_plugin_order`）。
   - 初始化屏幕方向锁定偏好（默认锁定竖屏）与主题偏好。
2. **声明式路由导航 (`go_router`)**：
   - 集中维护路由拓扑：`/` (主页)、`/manager` (插件管理中心)、`/settings` (设置)、`/plugin/:path` (动态插件宿主容器)。
   - 配合 Android 13+ 预测式返回（`android:enableOnBackInvokedCallback="true"`），在二级页面保护用户手势，防止误退出。
3. **全局状态流与控制 (`flutter_riverpod`)**：
   - `pluginRegistryProvider`: 插件注册、启用状态、双向排序同步与持久化。
   - `themeModeProvider`: 主题模式（品牌深色 / 清新浅色 / 跟随系统）。
   - `dynamicColorEnabledProvider`: Material You 壁纸动态取色开关控制。
   - `autoRotateProvider`: 重力旋转屏幕开关。
4. **原生组件与资源**：
   - 配置 Android 原生各分辨率启动图标（`res/mipmap-*`）。
   - 注册并装载应用矢量及位图资源（`assets/icons/`）。

---

## 目录结构

```
app/
├── android/                  # Android 原生配置、Manifest 与 Gradle 脚本
├── assets/
│   └── icons/                # 应用高分辨率图标与矢量 SVG 图标
├── lib/
│   ├── main.dart             # 程序唯一入口点，启动 ProviderScope
│   └── src/
│       ├── app.dart          # MaterialApp 顶层容器，集成 DynamicColor 与主题监听
│       ├── home/             # 主页网格：扁平化无分类展示，支持长按拖拽排序
│       ├── plugin_manager/   # 插件管理中心：文件导入、启用开关、长按删除、左侧把手排序
│       ├── host/             # 动态插件运行时宿主页面，挂载 DUI 渲染树
│       ├── settings/         # 设置页面：外观显示设置、重力旋转、主题模式、动态取色、关于
│       ├── router/           # 声明式路由定义 (app_router.dart)
│       └── providers/        # 全局 Riverpod 提供者与持久化调度器 (app_providers.dart)
├── test/
│   └── widget_test.dart      # 宿主核心交互与容器断言（网格重排、管理中心手柄、删除弹窗、主题设置与错误降级）
└── pubspec.yaml              # 依赖声明与 assets 资源配置
```

---

## 依赖关系

本工程通过本地路径引用 monorepo 中的 packages：

```yaml
dependencies:
  flutter:
    sdk: flutter
  plugin_toolbox_core:
    path: ../packages/core
  plugin_toolbox_lua:
    path: ../packages/lua
  plugin_toolbox_dui:
    path: ../packages/dui
  plugin_toolbox_ui:
    path: ../packages/ui
  flutter_riverpod: ^2.6.1
  go_router: ^14.8.1
  reorderable_grid_view: ^2.2.8
  shared_preferences: ^2.3.0
  file_picker: ^8.1.4
  dynamic_color: ^1.7.0
```

---

## 页面与交互设计

### 1. 主界面 (`HomePage`)
- **无分类网格设计**：所有启用的插件平铺呈现在响应式网格中（竖屏 3 列，横屏 4 列）。
- **长按拖动排序**：基于 `ReorderableGridView`，长按任意插件卡片即可拖拽重排，排序结果实时保存并与管理中心完全同步。
- **空态引导**：未启用任何插件时展示优雅的空态指引按钮，一键跳转插件中心。

### 2. 插件管理中心 (`PluginManagerPage`)
- **安全防误触卸载**：去除显眼的垃圾桶按钮，改为**长按卡片**唤起二次确认弹窗，内置插件受保护无法卸载。
- **左侧手柄拖拽排序**：在插件卡片左侧图标区域提供明确的拖拽手柄，长按即可快速上下调整顺序。
- **平滑切换**：开关切换仅改变插件启用状态并实时持久化，不会误关闭当前管理页面。
- **一键导入**：右下角悬浮按钮直接调用系统文件选择器导入 `.ptx` 或 `.zip` 插件包。

### 3. 个性化设置 (`SettingsPage`)
- **主题模式切换**：支持「品牌深色（默认）」、「清新浅色」、「跟随系统」。
- **动态取色 (Material You)**：默认关闭以展现工具箱专享 `#26366A` 品牌色，用户可按需开启提取壁纸色彩。
- **重力旋转屏幕**：默认锁定竖屏，开启后跟随系统陀螺仪自适应旋转。
- **关于我们**：内嵌专属高质感工具箱品牌图标与版本声明。

---

## 本地开发与测试

### 1. 运行调试

```bash
# 获取依赖
flutter pub get

# 本地真机/模拟器调试运行
flutter run
```

### 2. 执行自动化测试套件

```bash
# 静态分析
cd .. && dart analyze

# 独立规则与规范验证
dart run tool/verify.dart

# 运行 App 模块单元测试与 Widget 测试（纯宿主软件测试，不测插件业务）
cd app && flutter test

# 真机视觉与布局截图验证（连接 Android 设备）
python ../tool/shots.py 01-home 02-manager 03-settings
```

### 3. 构建发布包

```bash
# 按 ABI 架构拆分生成轻量 Release APK
flutter build apk --release --split-per-abi

# 或构建调试包以便真机即时安装
flutter build apk --debug
adb install -r build/app/outputs/flutter-apk/app-debug.apk
```
