library;

// 模型与接口
export 'src/model/plugin_manifest.dart';
export 'src/model/plugin_permission.dart';
export 'src/model/plugin_category.dart';
export 'src/plugin/tool_plugin.dart';
export 'src/plugin/dynamic_plugin.dart';
export 'src/plugin/plugin_context.dart';
export 'src/plugin/plugin_registry.dart';
export 'src/plugin/plugin_list_controller.dart';
export 'src/plugin/plugin_ipc_broker.dart';

// 安装与加载
export 'src/installer/plugin_installer.dart';
export 'src/loader/plugin_loader.dart';

// 插件商店（远端目录拉取与安装包下载）
export 'src/store/plugin_store_entry.dart';
export 'src/store/plugin_store_exception.dart';
export 'src/store/plugin_package_inspection.dart';
export 'src/store/jsdelivr_plugin_store_source.dart';
export 'src/store/plugin_store_semantics.dart';

// 基础服务
export 'src/event/event_bus.dart';
export 'src/event/app_event.dart';
export 'src/storage/plugin_storage.dart';
export 'src/permission/permission_manager.dart';

// 沙箱安全
export 'src/sandbox/sandbox_path.dart';

// 工具类
export 'src/util/type_converter.dart';
