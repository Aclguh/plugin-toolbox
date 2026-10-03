# AGENTS.md

本文件记录本仓库的开发、架构设计、测试与发布规范，供人类开发者与 AI Agent 遵循。

---

## 提交规范

- 所有改动必须使用 **Conventional Commits** 规范：`feat:` / `fix:` / `docs:` / `refactor:` / `test:` / `chore:` 等。
- 提交正文写清**做了什么、为什么这么做**；如有方案取舍，需把权衡理由记录在提交信息中。
- 一次提交聚焦一件事。版本号变更与附属文档更新应单独或随当次功能发布一并清晰提交。
- **不主动 `git push`、不主动发布 Release**。一切推送与分发操作均需等待用户明确指令。
- 提交前务必执行 `git status`，严格确认只暂存了本次目标改动的文件，切勿随手将未受控的临时文件或他人改动纳入提交。
- 本仓库单人开发，主分支为 `master`。

---

## 完成前的验证门槛

在声明任务「已完成」之前，必须严格按顺序通过以下检查：

1. **静态代码分析**：
   - 仓库根目录执行 `dart analyze`。
   - 必须保持 **0 errors, 0 warnings, 0 issues**。
2. **单元测试与 Widget 测试**：
   - 运行各模块测试：`cd packages/ui && flutter test` 以及 `cd app && flutter test`。
   - 全部测试用例必须 100% 通过（包括主页网格拖拽重排、插件管理中心长按删除与拖拽手柄、设置页主题模式切换等）。
3. **动态插件端到端验证**：
   - `app/test/ptx_integration_test.dart` 测试 `.ptx` 插件安装、Lua 脚本执行、DUI 界面渲染与编解码数据流闭环。
4. **真机运行验证（设备就绪时）**：
   - 通过 `adb devices` 确认 Android 测试设备已连接（如 `7c2af7741023`）。
   - 编译并安装调试包：`flutter build apk --debug && adb -s <device-id> install -r app/build/app/outputs/flutter-apk/app-debug.apk`。
   - 启动应用并截屏检查：
     - **严禁出现布局溢出**（无红底白字 `A RenderFlex overflowed...`、无黄黑交替警告斑马条）。
     - **主题色与字体**：主界面及各插件背景必须为 `#26366A`，主要字体颜色必须为 `#B4C9FF`。
     - **手势与导航**：返回键/手势在二级页面时必须返回上一级，而非直接退出应用；插件管理中心开关切换不会误触发页面弹出。

---

## 项目架构与 Monorepo 依赖规范

本工程采用清晰的 Monorepo 分层架构：

```
plugin-toolbox/
├── app/                  # Android 宿主壳工程（Flutter App）
├── packages/
│   ├── core/             # 核心领域层：模型、插件注册表、安装器、沙箱文件与事件总线
│   ├── lua/              # 脚本执行层：Lua 5.1/LuaJIT 引擎与安全宿主 API 绑定
│   ├── dui/              # 动态 UI 层：声明式 JSON -> Flutter 组件树解析与响应式状态
│   └── ui/               # 共享表现层：品牌主题系统 (AppTheme) 与可复用基础 UI 组件
└── sample_plugins/       # 官方示例动态插件源码及打包脚本（base64_tool, hash_tool 等）
```

### 模块边界与单向依赖规则

1. **`packages/core`（纯领域核心）**：
   - 仅依赖 Dart 基础类库与纯 Dart 第三方包（如 `archive`）。
   - **绝对禁止依赖 Flutter UI 类库**（严禁 import `package:flutter/...`）。
2. **`packages/lua` 与 `packages/dui`**：
   - 依赖 `packages/core`。
   - `lua` 负责数据与逻辑运算，通过 `SecurityPolicy` 与事件总线与系统通信。
   - `dui` 负责将 JSON UI 树映射为原生组件，并通过响应式状态绑定（`${state.xxx}`）同步 UI。
3. **`packages/ui`**：
   - 依赖 `packages/core` 与 `flutter`。
   - 集中维护应用主题规范（`AppColorSchemes`、`AppTheme`）与通用控件。
4. **`app`（宿主组装层）**：
   - 依赖以上所有模块，负责组装路由（`go_router`）、全局状态（`flutter_riverpod`）以及 Android 原生生命周期。

### 动态插件沙箱规范

- 动态插件（`.ptx`）本质为 Zip 压缩包，安装时解压至应用独立沙箱目录：`app_data/plugins/<plugin_id>/`。
- 插件的文件与持久化读写严禁跨越其根目录，防止路径穿越攻击（Path Traversal）。
- 插件卸载时，需同步清理其解压沙箱目录、持久化数据与注册表项。

---

## 插件系统与 `.ptx` 包规范

### 1. 包结构

每个 `.ptx` 文件必须包含以下核心文件：

```
<plugin_id>.ptx
├── manifest.json         # 插件清单与元数据配置（必须）
├── entry.lua             # 核心逻辑与业务脚本（必须）
├── ui.json               # 声明式 UI 描述文件（必须）
└── icon.png              # 插件专属图标，建议 128x128（可选）
```

### 2. `manifest.json` 关键字段

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

### 3. 生命周期与同步

- 插件按状态分为**已启用 (enabled)** 与**已禁用 (disabled)**。
- **排序持久化**：存储于 `SharedPreferences` 中的 `plugin_toolbox_plugin_order`。
- **双向排序一致性**：主界面网格拖拽排序与插件管理中心的拖拽手柄排序使用同一数据源，两处变动严格实时同步。

---

## 界面与主题规范

### 1. 默认品牌主题色（提取自应用矢量图标 SVG）

- **主背景色**：`#26366A`（深邃藏蓝背景）。
- **主要字体色**：`#B4C9FF`（清爽冰蓝高对比字体，对比度达 7.4:1，超越 WCAG AAA 标准）。
- **次要字体色**：`#8EA4D8`（用于描述、辅助提示、版本信息）。
- **主交互提色 (Primary)**：`#788CFF`（把手与主要按钮靛青色）。
- **卡片/容器底色 (SurfaceContainerLow)**：`#1B2445`（工具箱内槽凹陷色，保证与主背景对比）。
- **辅助青色 (Secondary)**：`#31D9D0`（薄荷青光圈色，用于开关等状态提色）。
- **辅助珊瑚色 (Tertiary)**：`#FF9D72`（珊瑚粉色）。

### 2. 主题与取色策略

- 默认主题模式设为 **品牌深色（默认）**（`ThemeMode.dark`）。
- **动态取色 (Material You) 默认关闭**：避免 Android 12+ 手机系统壁纸颜色强行覆盖工具箱精心设计的品牌色；在「设置」页提供手动开启开关。
- 支持在「设置」中随时切换：`品牌深色（默认）` / `清新浅色` / `跟随系统`。

### 3. 屏幕旋转与显示

- **默认锁定竖屏**（`DeviceOrientation.portraitUp`）。
- 在设置页提供「重力旋转屏幕」开关，开启后响应系统重力感应。
- 针对手机横竖屏切换，主页网格需自适应调整 `crossAxisCount`（竖屏 3 列，横屏 4 列）与 `childAspectRatio`，确保图标和文字无溢出。

---

## 状态管理与持久化规范

1. **统一采用 Riverpod**：
   - 业务状态管理使用 `StateNotifier` + `StateNotifierProvider`。
   - 异步加载使用 `FutureProvider`。
2. **容错与容空机制**：
   - 访问 `SharedPreferences` 必须包裹 `try-catch` 或采用安全容空设计，确保测试环境或存储故障时应用依然正常降级运行，绝不可引发崩溃。
3. **状态隔离与重置**：
   - 编写单元或 Widget 测试时，必须在 `setUp` 中执行 `SharedPreferences.setMockInitialValues({})`，防止跨测试用例状态残留。

---

## 版本与发布规范

### 1. 版本号同步规则

每次版本变更，必须同步更新以下三处：
1. `app/pubspec.yaml` 中的 `version: X.Y.Z+N`。
2. `app/lib/src/settings/settings_page.dart` 中关于项的显示文字。
3. `app/test/widget_test.dart` 中的相关版本断言。

### 2. 发布打包命令

```bash
cd app
flutter build apk --release --split-per-abi
```

发布前需对生成的 APK 文件进行校验：
- **架构分离**：产物应包含 `arm64-v8a`、`armeabi-v7a` 及 `x86_64`。
- **体积检查**：记录精确字节数（`ls -la`），关注 `libapp.so` 的大小变化。
- **SHA-256**：计算各架构 APK 的 SHA-256 校验和并写入 Release 文档。

---

## 代码风格与整洁规范

- **不滥用 Emoji**：界面文案、技术文档与代码注释中保持专业克制，除必要说明外不随意堆砌表情符号。
- **注释准则**：代码注释专注于阐明**为什么这么做（Why）**与边界原因，规范准则集中沉淀在 `AGENTS.md`。
- **文档完整性**：新增/删除模块时，必须同步更新各级 `README.md` 中的架构图、目录树与功能清单。
