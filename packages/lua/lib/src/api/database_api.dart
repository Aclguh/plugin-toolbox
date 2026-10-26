import 'dart:io';

import 'package:lua_dardo/lua.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';

import '../lua_callback_invoker.dart';
import '../lua_value_codec.dart';
import 'plugin_database.dart';
import 'sandbox_database_engine.dart';

/// `db` — 插件独立沙箱内的轻量结构化数据库 API。
///
/// 严格限定于插件沙箱独立文件 (`<sandbox>/plugin_data.db`)，
/// 默认提供纯 Dart 实现的无依赖结构化 SQL 查询与增删改查引擎，
/// 亦支持注入 [PluginDatabaseFactory] 接入原生驱动。
class DatabaseApi {
  final PluginDatabaseFactory? databaseFactory;
  PluginDatabase? _engine;

  DatabaseApi({this.databaseFactory});

  static void bind(
    LuaState ls,
    PluginContext context,
    LuaCallbackInvoker callbacks, {
    PluginDatabaseFactory? databaseFactory,
  }) {
    final api = DatabaseApi(databaseFactory: databaseFactory);
    api.bindInstance(ls, context, callbacks);
  }

  void bindInstance(
    LuaState ls,
    PluginContext context,
    LuaCallbackInvoker callbacks,
  ) {
    ls.newTable();

    // database 为独立权限语义：storage 仅代表键值/文件存储，
    // 结构化数据库读写必须显式声明 database 权限。
    void checkPermission(LuaState ls) {
      if (!context.hasPermission(PluginPermission.database)) {
        ls.error2('权限不足: 插件未声明 database 权限');
      }
    }

    final rootDir = context.rootDir;
    if (rootDir == null) {
      // 无沙箱 rootDir 时显式抛错降级：退化为 CWD 相对路径写库会把插件数据
      // 落到应用工作目录，破坏沙箱隔离且卸载时无法清理。
      for (final name in ['execute', 'query', 'batch', 'flush']) {
        ls.pushDartFunction((ls) {
          checkPermission(ls);
          ls.error2('沙箱未挂载: database API 需要插件沙箱 rootDir');
          return 0;
        });
        ls.setField(-2, name);
      }
      ls.setGlobal('db');
      return;
    }

    final dbFile = File('${rootDir.path}/plugin_data.db');
    final dbEngine = databaseFactory != null
        ? databaseFactory!(dbFile)
        : SandboxDatabaseEngine(
            dbFile: dbFile,
            eventBus: context.eventBus,
            logger: context.logger,
            pluginId: context.pluginId,
          );
    _engine = dbEngine;

    // db.execute(sql [, paramsList | callback, callback])
    ls.pushDartFunction((ls) {
      checkPermission(ls);
      final sql = ls.checkString(1) ?? '';
      List<dynamic> params = [];
      int? cbRef;

      if (ls.type(2) == LuaType.luaFunction) {
        cbRef = callbacks.ref(2);
      } else if (ls.type(2) == LuaType.luaTable) {
        ls.pushValue(2);
        final raw = LuaValueCodec.pop(ls);
        if (raw is List) params = raw;
        if (ls.type(3) == LuaType.luaFunction) {
          cbRef = callbacks.ref(3);
        }
      }

      dbEngine.execute(sql, params).then((res) {
        if (cbRef != null) {
          callbacks.invokeAndRelease(cbRef, [res]);
        }
      }).catchError((Object e) {
        if (cbRef != null) {
          callbacks.invokeAndRelease(cbRef, [
            {'ok': false, 'error': e.toString()}
          ]);
        }
      });
      return 0;
    });
    ls.setField(-2, 'execute');

    // db.query(sql [, paramsList | callback, callback])
    ls.pushDartFunction((ls) {
      checkPermission(ls);
      final sql = ls.checkString(1) ?? '';
      List<dynamic> params = [];
      int? cbRef;

      if (ls.type(2) == LuaType.luaFunction) {
        cbRef = callbacks.ref(2);
      } else if (ls.type(2) == LuaType.luaTable) {
        ls.pushValue(2);
        final raw = LuaValueCodec.pop(ls);
        if (raw is List) params = raw;
        if (ls.type(3) == LuaType.luaFunction) {
          cbRef = callbacks.ref(3);
        }
      }

      dbEngine.query(sql, params).then((res) {
        if (cbRef != null) {
          callbacks.invokeAndRelease(cbRef, [res]);
        }
      }).catchError((Object e) {
        if (cbRef != null) {
          callbacks.invokeAndRelease(cbRef, [
            {'ok': false, 'error': e.toString(), 'rows': <dynamic>[]}
          ]);
        }
      });
      return 0;
    });
    ls.setField(-2, 'query');

    // db.batch(statementsList, callback)
    ls.pushDartFunction((ls) {
      checkPermission(ls);
      ls.pushValue(1);
      final rawStatements = LuaValueCodec.pop(ls);
      final cbRef = callbacks.ref(2);

      final list = <Map<String, dynamic>>[];
      if (rawStatements is List) {
        for (final item in rawStatements) {
          if (item is Map) {
            list.add(item.cast<String, dynamic>());
          } else if (item is String) {
            list.add({'sql': item, 'params': []});
          }
        }
      }

      if (cbRef != null) {
        dbEngine.batch(list).then((res) {
          callbacks.invokeAndRelease(cbRef, [res]);
        }).catchError((Object e) {
          callbacks.invokeAndRelease(cbRef, [
            {'ok': false, 'error': e.toString()}
          ]);
        });
      }
      return 0;
    });
    ls.setField(-2, 'batch');

    // db.flush([callback]) - 显式将内存缓冲区改动即时刷入磁盘
    ls.pushDartFunction((ls) {
      checkPermission(ls);
      int? cbRef;
      if (ls.type(1) == LuaType.luaFunction) {
        cbRef = callbacks.ref(1);
      }
      dbEngine.flush().then((res) {
        if (cbRef != null) {
          callbacks.invokeAndRelease(cbRef, [res]);
        }
      }).catchError((Object e) {
        if (cbRef != null) {
          callbacks.invokeAndRelease(cbRef, [
            {'ok': false, 'error': e.toString()}
          ]);
        }
      });
      return 0;
    });
    ls.setField(-2, 'flush');

    ls.setGlobal('db');
  }

  void dispose() {
    _engine?.dispose();
    _engine = null;
  }
}
