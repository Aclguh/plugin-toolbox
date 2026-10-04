<div align="center">

<img src="app/assets/icons/plugin-toolbox-icon.png" width="128" alt="PluginToolbox 图标" />

# PluginToolbox

**PluginToolbox —— 基于轻量沙箱与动态声明式 UI 的 Android 插件工具箱**

一个高度解耦、完全离线、支持热插拔的现代化 Android 工具箱应用。无需重新编译宿主，用户只需导入一个 `.ptx` 插件包，即可即时运行全新功能。

[![Flutter](https://img.shields.io/badge/Flutter-3.29+-02569B?logo=flutter)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.7+-0175C2?logo=dart)](https://dart.dev)
[![Platform](https://img.shields.io/badge/Platform-Android-3DDC84?logo=android)](#安装与运行)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Architecture](https://img.shields.io/badge/Architecture-Monorepo-orange.svg)](#架构设计)
[![CI](https://github.com/Aclguh/plugin-toolbox/actions/workflows/ci.yml/badge.svg)](https://github.com/Aclguh/plugin-toolbox/actions/workflows/ci.yml)

**简体中文** · [English](README.en.md)

</div>

---

## 核心特性

- **动态热插拔插件生态**：
  - 基于标准 Zip 归档格式的 `.ptx` (Plugin Toolbox Extension) 插件包，支持一键安装、即刻启用与安全卸载。
  - 每个动态插件拥有独立沙箱存储空间，防止插件间数据污染与越权访问。
- **声明式动态 UI (DUI)**：
  - 纯 JSON 描述组件树，由宿主运行时原生映射为高性能 Flutter Widget。
  - 支持响应式数据绑定与事件驱动机制，无需编写复杂的前端逻辑。
- **轻量受控脚本引擎**：
  - 内置沙箱级 Lua 脚本运行时，兼具高性能与轻量化。
  - 提供安全宿主 API 集合：剪贴板、沙箱存储、系统信息。


---

## 架构设计

本工程采用清晰的 Monorepo 分层架构，各子模块职责单一、单向依赖：

```
plugin-toolbox/
├── app/                  # Android 宿主主工程（Flutter App）
│   ├── lib/              # 页面、路由 (go_router)、全局状态 (Riverpod)
│   └── test/             # 宿主 Widget 测试与组件交互测试
├── packages/
│   ├── core/             # 领域核心：插件模型、注册中心、安装器与沙箱安全（纯 Dart）
│   ├── lua/              # 脚本执行层：Lua 脚本引擎与沙箱 API 绑定（含指令数预算防护）
│   ├── dui/              # 声明式 UI 引擎：JSON AST -> Flutter Widget 动态渲染
│   ├── ui/               # 共享表现层：AppTheme 品牌主题系统与通用组件库
│   └── third_party/
│       └── lua_dardo/    # Lua VM 本地维护分支 (Apache-2.0)：新增指令数预算能力
├── sample_plugins/       # 官方样例插件源码与打包脚本 (pack.py)
│   ├── base64_tool/      # Base64 文本编解码插件
│   └── hash_tool/        # MD5 / SHA-1 / SHA-256 哈希计算插件
├── tool/                 # 独立质量工程工具套件 (verify.dart, shots.py)
├── .github/workflows/    # CI 流水线：analyze + verify + 全模块测试
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
    Core->>Core: 解压校验 plugin.json 并建立沙箱目录
    Core->>App: 注册插件至 PluginRegistry
    User->>App: 点击插件卡片进入
    App->>Lua: 初始化 Lua 插件运行时与隔离存储
    App->>DUI: 解析 UI 定义构建组件树并绑定 state
    DUI->>User: 渲染原生 Flutter 交互页面
    User->>DUI: 触发界面交互（如点击转换）
    DUI->>Lua: 派发事件至 Lua 全局处理函数
    Lua->>Lua: 执行业务逻辑并调用宿主 API 更新状态
    Lua-->>DUI: 更新响应式状态
    DUI-->>User: 局部刷新视图结果
```

---

## `.ptx` 插件规范与编写指南

一个标准的 `.ptx` 实际上是一个普通的 Zip 归档包（后缀为 `.ptx`），由宿主在安装时
解压至插件独立沙箱目录。插件包结构、清单字段、声明式 UI 语法与宿主 Lua API 以仓库
生产实现为准，可直接参考官方样例 `sample_plugins/`（base64_tool、hash_tool）。

### 插件跨平台打包 (`sample_plugins/pack.py`)

在工程根目录下执行跨平台 Python 打包脚本：

```bash
# 一键打包所有插件目录为 .ptx
python sample_plugins/pack.py

# 或打包指定插件
python sample_plugins/pack.py base64_tool
```

---

## 安装与运行

### 1. 从源码编译

要求环境：
- Flutter SDK 3.29+ / Dart SDK 3.7+
- Android SDK (API 34+), Java 17+
- Python 3.10+ (用于质量工具与插件打包)

```bash
# 克隆仓库
git clone https://github.com/Aclguh/plugin-toolbox.git
cd plugin-toolbox

# 安装依赖
flutter pub get
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


```bash
# 1. 静态代码分析（保持 0 错误 0 警告）
dart analyze

# 2. 独立规范与逻辑自动化验证（纯 Dart 快速执行，80 项断言全通过）
dart run tool/verify.dart

# 3. 分层单元测试与 Widget 测试（纯软件架构与宿主交互测试，无需外部设备，共 70 用例）
cd packages/core && flutter test
cd packages/lua && flutter test
cd packages/dui && flutter test
cd packages/ui && flutter test
cd app && flutter test

# 4. 真机截图与视觉规范验证（需连接真机，自动裁剪系统栏并压缩）
python tool/shots.py 01-home 02-manager 03-settings
```

### 统一任务入口 (melos)

```bash
melos run analyze        # 各包静态分析
melos run test           # 各包测试
melos run verify         # 独立验证套件
melos run pack:plugins   # 打包示例插件
melos run build:apk      # 构建发布 APK
```

---


## 许可证与致谢

- 本项目源码采用 [MIT License](LICENSE) 授权开源。
- 核心依赖致谢：
  - [Flutter](https://flutter.dev) & [Dart](https://dart.dev)
  - [Riverpod](https://riverpod.dev) —— 高性能响应式状态管理框架
  - [GoRouter](https://pub.dev/packages/go_router) —— 声明式路由导航
  - [Archive](https://pub.dev/packages/archive) —— 高性能跨平台解压缩引擎
  - [ReorderableGridView](https://pub.dev/packages/reorderable_grid_view) —— 流畅的网格拖拽排序支持
