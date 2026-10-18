import 'package:lua_dardo/lua.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';

import '../delegates/domain_delegates.dart';
import '../lua_callback_invoker.dart';
import 'fs/fs_basic_handler.dart';
import 'fs/fs_binary_handler.dart';
import 'fs/fs_external_handler.dart';
import 'fs/fs_hash_handler.dart';

/// `fs` — 沙箱文件系统 API 统一入口。
///
/// 严格受限于插件独立沙箱目录（`app_data/plugins/<id>/`），
/// 所有路径操作经 [SandboxPath.isSafeSubpath] 校验，绝不发生路径穿越。
class FsApi {
  static void bind(
    LuaState ls,
    PluginContext context,
    LuaHostDelegate delegate,
    LuaCallbackInvoker callbacks,
  ) {
    ls.newTable();

    FsBasicHandler.register(ls, context, callbacks);
    FsBinaryHandler.register(ls, context, callbacks);
    FsExternalHandler.register(ls, context, delegate, callbacks);
    FsHashHandler.register(ls, context, callbacks);

    ls.setGlobal('fs');
  }
}
