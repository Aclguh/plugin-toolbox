# PluginToolbox

万物皆插件——以插件为核心架构的 Android 工具箱。

用户导入一个 `.ptx` 插件包即可直接使用，无需重新编译应用。

## 架构概览

- `app/`: 主应用壳（Flutter App），提供路由、主页网格、插件管理和动态宿主。
- `packages/core/`: 核心模型、插件系统、安装器与隔离服务。
- `packages/lua/`: Lua 脚本运行时引擎与安全宿主 API 绑定。
- `packages/dui/`: 声明式 UI (JSON -> Flutter Widget) 渲染引擎。
- `packages/ui/`: 共享 UI 组件和 Material Design 3 主题系统。
- `sample_plugins/`: 示例 `.ptx` 插件源文件与打包工具。
