<div align="center">

<img src="app/assets/icons/plugin-toolbox-icon.png" width="128" alt="PluginToolbox 图标" />

# PluginToolbox

**万物皆插件 —— 基于轻量沙箱与动态声明式 UI 的 Android 插件工具箱**

一个高度解耦、完全离线、支持热插拔的现代化 Android 工具箱应用。无需重新编译宿主，用户只需导入一个 `.ptx` 插件包，即可即时运行全新功能。

[![Flutter](https://img.shields.io/badge/Flutter-3.29+-02569B?logo=flutter)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.7+-0175C2?logo=dart)](https://dart.dev)
[![Platform](https://img.shields.io/badge/Platform-Android-3DDC84?logo=android)](#安装与运行)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Architecture](https://img.shields.io/badge/Architecture-Monorepo-orange.svg)](#架构设计)

**简体中文** · [English](README.en.md)

</div>

---

## 核心特性

- **动态热插拔插件生态**：
  - 基于标准 Zip 归档格式的 `.ptx` (Plugin Toolbox Extension) 插件包，支持一键安装、即刻启用与安全卸载。
  - 每个动态插件拥有独立沙箱存储空间，防止插件间数据污染与越权访问。
- **声明式动态 UI (DUI)**：
  - 纯 JSON 描述组件树（`ui.json`），由宿主运行时原生映射为高性能 Flutter Widget。
  - 支持 `${state.key}` 响应式数据绑定与事件驱动机制，无需编写复杂的前端逻辑。
- **轻量受控脚本引擎**：
  - 内置沙箱级 Lua 脚本运行时（`entry.lua`），兼具高性能与轻量化。
  - 提供安全宿主 API 集合：剪贴板（`toolbox.clipboard`）、沙箱存储（`toolbox.storage`）、系统信息与日志追踪。
- **直观的双向排序与管理体系**：
  - **主页**：扁平化无分类网格，支持长按自由拖拽排序。
  - **插件管理中心**：集成启用/禁用开关、长按卡片安全卸载，并通过左侧拖拽手柄实现与主页严格实时的排序同步。
- **专属定制品牌视觉**：
  - 深度提炼自应用矢量图标的品牌调色方案：默认以 `#26366A` 为深邃藏蓝背景，`#B4C9FF` 为高对比度冰蓝文字（对比度超 7.4:1，达 WCAG AAA 级）。
  - 内建品牌深色、清新浅色与跟随系统选项，支持 Android 12+ Material You 动态取色按需开启。
- **设备适配与手势保护**：
  - 默认锁定竖屏体验，提供重力感应旋转开关，自适应多端横竖屏网格排版。
  - 支持 Android 13+ Predictive Back 预测式返回，二级页面防误触退出。

---

## 架构设计

本工程采用清晰的 Monorepo 分层架构，各子模块职责单一、单向依赖：

```
plugin-toolbox/
├── app/                  # Android 宿主主工程（Flutter App）
│   ├── lib/              # 页面、路由 (go_router)、全局状态 (Riverpod)
│   └── test/             # Widget 测试与端到端插件集成测试
├── packages/
│   ├── core/             # 领域核心：插件模型、注册中心、安装器与隔离服务（纯 Dart）
│   ├── lua/              # 脚本执行层：Lua 5.1/LuaJIT 脚本引擎与沙箱 API 绑定
│   ├── dui/              # 声明式 UI 引擎：JSON AST -> Flutter Widget 动态渲染
│   └── ui/               # 共享表现层：AppTheme 品牌主题系统与通用组件库
├── sample_plugins/       # 官方样例插件源码与打包打包脚本
│   ├── base64_tool/      # Base64 文本编解码插件
│   └── hash_tool/        # MD5 / SHA-1 / SHA-256 哈希计算插件
└── AGENTS.md             # 统一架构标准、开发门槛与 AI Agent 协作规范
```

### 插件加载与运行流程

```mermaid
sequenceDiagram
    autonumber
    actor User as 用户
    participant App as 宿主壳 (app)
    participant Core as 核心层 (packages/core)
    participant Lua as Lua 引擎 (packages/lua)
    participant DUI as 声明式 UI (packages/dui)

    User->>App: 导入 .ptx 文件
    App->>Core: PluginInstaller.installFromPtx(file)
    Core->>Core: 解压校验 manifest.json 并建立沙箱目录
    Core->>App: 注册插件至 PluginRegistry
    User->>App: 点击插件卡片进入
    App->>Lua: 初始化 Lua 插件运行时与隔离存储
    App->>DUI: 解析 ui.json 构建组件树并绑定 state
    DUI->>User: 渲染原生 Flutter 交互页面
    User->>DUI: 触发界面交互（如点击转换）
    DUI->>Lua: 派发事件 eventHandler.emit('encode')
    Lua->>Lua: 执行业务逻辑并调用 toolbox.ui.set_state(...)
    Lua-->>DUI: 更新响应式状态
    DUI-->>User: 局部刷新视图结果
```

---

## `.ptx` 插件规范与编写指南

一个标准的 `.ptx` 实际上是一个普通的 Zip 归档包（后缀为 `.ptx`），其根目录下包含以下文件：

```
my_plugin.ptx
├── manifest.json         # 插件清单与元数据（必选）
├── entry.lua             # 核心逻辑脚本（必选）
├── ui.json               # 声明式组件树定义（必选）
└── icon.png              # 插件图标，推荐 128x128 PNG（可选）
```

### 1. 插件清单 (`manifest.json`)

```json
{
  "id": "base64_tool",
  "name": "Base64 编解码",
  "version": "1.0.0",
  "description": "Base64 文本编码与解码转换工具",
  "author": "PluginToolbox Team",
  "type": "lua",
  "category": "utility",
  "entry": "entry.lua",
  "ui": "ui.json",
  "permissions": ["storage", "clipboard"]
}
```

### 2. 声明式 UI (`ui.json`)

```json
{
  "type": "Column",
  "props": {
    "crossAxisAlignment": "stretch"
  },
  "children": [
    {
      "type": "TextField",
      "props": {
        "label": "输入文本",
        "value": "${state.input_text}",
        "maxLines": 4
      },
      "events": {
        "onChanged": "on_input_changed"
      }
    },
    {
      "type": "Row",
      "children": [
        {
          "type": "ElevatedButton",
          "props": { "label": "编码" },
          "events": { "onTap": "on_encode" }
        }
      ]
    },
    {
      "type": "Card",
      "children": [
        {
          "type": "Text",
          "props": { "text": "${state.result_text}" }
        }
      ]
    }
  ]
}
```

### 3. 业务脚本 (`entry.lua`)

```lua
-- 初始化插件状态
toolbox.ui.set_state({
    input_text = "",
    result_text = ""
})

-- 输入文本监听
function on_input_changed(value)
    toolbox.ui.set_state({ input_text = value })
end

-- 编码点击事件
function on_encode()
    local text = toolbox.ui.get_state("input_text") or ""
    local encoded = toolbox.crypto.base64_encode(text)
    toolbox.ui.set_state({ result_text = encoded })
end
```

### 4. 一键打包脚本 (`pack.py`)

在插件源码根目录下执行：

```bash
python pack.py
# 将在 dist/ 目录下自动生成经过校验的 <plugin_id>.ptx
```

---

## 主题设计系统

应用的默认主题全面提取自矢量品牌图标（`plugin-toolbox-icon.svg`）：

| 界面角色 | 取色 Hex | 语义与视觉考量 |
| :--- | :--- | :--- |
| **主背景色 (Scaffold / Surface)** | **`#26366A`** | 深邃沉稳的藏蓝底色，奠定专业工具箱质感 |
| **主字体色 (onSurface / Typography)** | **`#B4C9FF`** | 清爽冰蓝色，对比度高达 7.4:1，极佳的阅读舒适度 |
| **次级字体色 (onSurfaceVariant)** | `#8EA4D8` | 柔和浅蓝紫，用于次级提示、说明文字与版本号 |
| **主交互提色 (Primary)** | `#788CFF` | 活力靛青把手主色，用于按钮、重点交互指示 |
| **容器卡片底色 (SurfaceContainerLow)** | `#1B2445` | 工具箱内槽深色，提供清晰而不刺眼的卡片层级 |
| **辅助状态色 (Secondary / Tertiary)** | `#31D9D0` / `#FF9D72` | 薄荷青与珊瑚粉，用于状态开关、徽标与警示 |

---

## 安装与运行

### 1. 从源码编译

要求环境：
- Flutter SDK 3.29+ / Dart SDK 3.7+
- Android SDK (API 34+), Java 17+
- Python 3.10+ (仅用于插件打包与图标脚本)

```bash
# 克隆仓库
git clone https://github.com/Aclguh/plugin-toolbox.git
cd plugin-toolbox

# 安装依赖
cd app && flutter pub get

# 启动调试（需连接真机或启动模拟器）
flutter run
```

### 2. 生产打包 (Split APK)

为优化安装包体积，推荐按 ABI 拆分打包：

```bash
cd app
flutter build apk --release --split-per-abi
# 输出产物：
# - build/app/outputs/flutter-apk/app-arm64-v8a-release.apk (主流机型推荐)
# - build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk (老旧机型)
# - build/app/outputs/flutter-apk/app-x86_64-release.apk (模拟器)
```

---

## 验证与测试

我们在开发过程中贯彻严格的自动化测试门槛（详见 [AGENTS.md](AGENTS.md)）：

```bash
# 1. 静态代码分析（保持 0 警告 0 错误）
dart analyze

# 2. 共享表现层测试
cd packages/ui && flutter test

# 3. 宿主集成测试与 Widget 测试（包含真机交互与拖拽断言）
cd ../../app && flutter test

# 4. 动态插件 E2E 验证（测试 .ptx 安装与数据流运转）
flutter test test/ptx_integration_test.dart
```

---

## 参与贡献与协作指南

欢迎参与 PluginToolbox 的开发！在提交 PR 或进行重大功能重构前，请务必详细阅读：

👉 **[AGENTS.md (开发者与 AI Agent 协作规范)](AGENTS.md)**

该规范详细阐明了提交信息格式（Conventional Commits）、单向架构约束、多端布局溢出规避指南以及版本发布准则。

---

## 许可证与致谢

- 本项目源码采用 [MIT License](LICENSE) 授权开源。
- 核心依赖致谢：
  - [Flutter](https://flutter.dev) & [Dart](https://dart.dev)
  - [Riverpod](https://riverpod.dev) —— 高性能响应式状态管理框架
  - [GoRouter](https://pub.dev/packages/go_router) —— 声明式路由导航
  - [Archive](https://pub.dev/packages/archive) —— 高性能跨平台解压缩引擎
  - [ReorderableGridView](https://pub.dev/packages/reorderable_grid_view) —— 流畅的网格拖拽排序支持
