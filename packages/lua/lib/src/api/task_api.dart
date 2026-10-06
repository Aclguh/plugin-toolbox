import 'dart:async';
import 'dart:isolate';

import 'package:lua_dardo/lua.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';

import '../lua_callback_invoker.dart';
import '../lua_value_codec.dart';
import 'codec_api.dart';
import 'crypto_api.dart';
import 'hash_api.dart';
import 'json_api.dart';
import 'regex_api.dart';

/// `task` — 后台并发计算与异步 Worker 调度 API。
///
/// 允许插件将计算密集型运算（大文本解析、散列校验、数学运算、复杂正则）
/// 调度至独立的 Dart Isolate 后台执行，避免阻塞主线程及 UI 渲染。
class TaskApi {
  static void bind(
    LuaState ls,
    PluginContext context,
    LuaCallbackInvoker callbacks,
  ) {
    ls.newTable();

    // task.run(script [, args [, optionsTable | callback, callback]])
    ls.pushDartFunction((ls) {
      final script = ls.checkString(1) ?? '';
      dynamic args;
      int timeoutMs = 5000;
      int budget = 1000000;
      int? cbRef;

      // 解析形参重载:
      // task.run(script, callback)
      // task.run(script, args, callback)
      // task.run(script, args, { timeoutMs = 3000, budget = 500000 }, callback)
      if (ls.type(2) == LuaType.luaFunction) {
        cbRef = callbacks.ref(2);
      } else if (ls.type(2) != LuaType.luaNil && ls.type(2) != LuaType.luaNone) {
        ls.pushValue(2);
        args = LuaValueCodec.pop(ls);

        if (ls.type(3) == LuaType.luaFunction) {
          cbRef = callbacks.ref(3);
        } else if (ls.type(3) == LuaType.luaTable) {
          ls.getField(3, 'timeoutMs');
          if (ls.isInteger(-1)) timeoutMs = ls.toInteger(-1);
          ls.pop(1);

          ls.getField(3, 'budget');
          if (ls.isInteger(-1)) budget = ls.toInteger(-1);
          ls.pop(1);

          if (ls.type(4) == LuaType.luaFunction) {
            cbRef = callbacks.ref(4);
          }
        }
      }

      unawaited(
        _executeIsolated(
          script: script,
          args: args,
          timeoutMs: timeoutMs,
          instructionBudget: budget,
        ).then((res) {
          if (cbRef != null) {
            callbacks.invokeAndRelease(cbRef, [res]);
          }
        }).catchError((Object e) {
          if (cbRef != null) {
            callbacks.invokeAndRelease(cbRef, [
              {'ok': false, 'error': e.toString()}
            ]);
          }
        }),
      );

      return 0;
    });
    ls.setField(-2, 'run');

    // task.parallel(taskListTable, callback)
    // taskListTable: { { script = "...", args = ... }, ... }
    ls.pushDartFunction((ls) {
      ls.pushValue(1);
      final rawTasks = LuaValueCodec.pop(ls);
      final cbRef = callbacks.ref(2);

      if (rawTasks is! List) {
        if (cbRef != null) {
          callbacks.invokeAndRelease(cbRef, [
            {'ok': false, 'error': 'task.parallel 第一个参数必须为任务配置列表数组'}
          ]);
        }
        return 0;
      }

      final taskFutures = <Future<Map<String, dynamic>>>[];
      for (final t in rawTasks) {
        if (t is Map) {
          final script = (t['script'] ?? '').toString();
          final args = t['args'];
          final timeoutMs = (t['timeoutMs'] as num?)?.toInt() ?? 5000;
          final budget = (t['budget'] as num?)?.toInt() ?? 1000000;
          taskFutures.add(_executeIsolated(
            script: script,
            args: args,
            timeoutMs: timeoutMs,
            instructionBudget: budget,
          ));
        } else {
          taskFutures.add(Future.value({
            'ok': false,
            'error': '任务配置必须为对象字典',
          }));
        }
      }

      unawaited(
        Future.wait(taskFutures).then((results) {
          if (cbRef != null) {
            callbacks.invokeAndRelease(cbRef, [
              {'ok': true, 'results': results}
            ]);
          }
        }).catchError((Object e) {
          if (cbRef != null) {
            callbacks.invokeAndRelease(cbRef, [
              {'ok': false, 'error': e.toString()}
            ]);
          }
        }),
      );

      return 0;
    });
    ls.setField(-2, 'parallel');

    ls.setGlobal('task');
  }

  static Future<Map<String, dynamic>> _executeIsolated({
    required String script,
    required dynamic args,
    required int timeoutMs,
    required int instructionBudget,
  }) async {
    try {
      final work = Isolate.run(() {
        return _isolateWorker(
          script: script,
          args: args,
          instructionBudget: instructionBudget,
        );
      });

      if (timeoutMs > 0) {
        return await work.timeout(
          Duration(milliseconds: timeoutMs),
          onTimeout: () => {
            'ok': false,
            'error': 'Task 执行超时 (${timeoutMs}ms)',
          },
        );
      }
      return await work;
    } catch (e) {
      return {'ok': false, 'error': e.toString()};
    }
  }

  static Map<String, dynamic> _isolateWorker({
    required String script,
    required dynamic args,
    required int instructionBudget,
  }) {
    final ls = LuaState.newState();
    ls.openLibs();

    // 禁用危险标准库
    for (final lib in [
      'os',
      'io',
      'debug',
      'package',
      'require',
      'dofile',
      'loadfile'
    ]) {
      ls.pushNil();
      ls.setGlobal(lib);
    }

    // 注入安全的工具库
    CodecApi.bind(ls);
    JsonApi.bind(ls);
    HashApi.bind(ls);
    CryptoApi.bind(ls);
    RegexApi.bind(ls);

    ls.setInstructionBudget(instructionBudget);

    final loadStatus = ls.loadString(script);
    if (loadStatus != ThreadStatus.luaOk) {
      final err = ls.toStr(-1) ?? 'Syntax error';
      ls.pop(1);
      return {'ok': false, 'error': '脚本语法错误: $err'};
    }

    // 执行脚本主体
    final pcallStatus = ls.pCall(0, 1, 0);
    if (pcallStatus != ThreadStatus.luaOk) {
      final err = ls.toStr(-1) ?? 'Execution error';
      ls.pop(1);
      return {'ok': false, 'error': '脚本执行失败: $err'};
    }

    final dynamic initialReturn = LuaValueCodec.pop(ls);

    // 检查是否定义了 main(args) 函数
    final mainType = ls.getGlobal('main');
    dynamic result;
    if (mainType == LuaType.luaFunction) {
      LuaValueCodec.push(ls, args);
      final callStatus = ls.pCall(1, 1, 0);
      if (callStatus != ThreadStatus.luaOk) {
        final err = ls.toStr(-1) ?? 'Error in main';
        ls.pop(1);
        return {'ok': false, 'error': 'main() 调用失败: $err'};
      }
      result = LuaValueCodec.pop(ls);
    } else {
      ls.pop(1); // 弹出非函数的 main
      result = initialReturn;
    }

    return {'ok': true, 'result': result};
  }
}
