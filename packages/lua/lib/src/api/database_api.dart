import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:lua_dardo/lua.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';

import '../lua_callback_invoker.dart';
import '../lua_value_codec.dart';

/// `db` — 插件独立沙箱内的轻量结构化数据库 API。
///
/// 严格限定于插件沙箱独立文件 (`<sandbox>/plugin_data.db`)，
/// 提供纯 Dart 实现的无依赖结构化 SQL 查询与增删改查引擎。
class DatabaseApi {
  static void bind(
    LuaState ls,
    PluginContext context,
    LuaCallbackInvoker callbacks,
  ) {
    ls.newTable();

    void checkPermission(LuaState ls) {
      if (!context.hasPermission(PluginPermission.database) &&
          !context.hasPermission(PluginPermission.storage)) {
        ls.error2('权限不足: 插件未声明 database 或 storage 权限');
      }
    }

    final dbPath = context.rootDir != null
        ? '${context.rootDir!.path}/plugin_data.db'
        : 'plugin_data_${context.pluginId}.db';
    final dbEngine = _SandboxDatabaseEngine(
      dbFile: File(dbPath),
    );

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

    ls.setGlobal('db');
  }
}

/// 纯 Dart 轻量沙箱结构化存储引擎
class _SandboxDatabaseEngine {
  final File dbFile;
  Map<String, List<Map<String, dynamic>>> _tables = {};
  Future<void>? _loadFuture;
  Future<dynamic> _opQueue = Future.value();

  _SandboxDatabaseEngine({required this.dbFile});

  Future<void> _ensureLoaded() {
    return _loadFuture ??= _doLoad();
  }

  Future<void> _doLoad() async {
    if (await dbFile.exists()) {
      try {
        final content = await dbFile.readAsString();
        final decoded = json.decode(content);
        if (decoded is Map<String, dynamic>) {
          _tables = decoded.map((k, v) => MapEntry(
                k,
                (v as List)
                    .map((item) => Map<String, dynamic>.from(item as Map))
                    .toList(),
              ));
        }
      } catch (_) {
        _tables = {};
      }
    }
  }

  Future<void> _persist() async {
    try {
      if (!await dbFile.parent.exists()) {
        await dbFile.parent.create(recursive: true);
      }
      await dbFile.writeAsString(json.encode(_tables));
    } catch (_) {}
  }

  Future<Map<String, dynamic>> execute(
      String rawSql, List<dynamic> params) {
    final completer = Completer<Map<String, dynamic>>();
    _opQueue = _opQueue.whenComplete(() async {
      try {
        await _ensureLoaded();
        final res = await _executeInternal(rawSql, params);
        completer.complete(res);
      } catch (e) {
        completer.complete({'ok': false, 'error': e.toString()});
      }
    });
    return completer.future;
  }

  Future<Map<String, dynamic>> _executeInternal(
      String rawSql, List<dynamic> params) async {
    final sql = _cleanSql(rawSql);
    final upper = sql.toUpperCase();

    if (upper.startsWith('CREATE TABLE')) {
      final match = RegExp(
              r'^CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?([a-zA-Z0-9_]+)',
              caseSensitive: false)
          .firstMatch(sql);
      if (match == null) {
        return {'ok': false, 'error': '无效的 CREATE TABLE 语句'};
      }
      final tableName = match.group(1)!;
      _tables.putIfAbsent(tableName, () => []);
      await _persist();
      return {'ok': true, 'rowsAffected': 0};
    }

    if (upper.startsWith('DROP TABLE')) {
      final match = RegExp(
              r'^DROP\s+TABLE\s+(?:IF\s+EXISTS\s+)?([a-zA-Z0-9_]+)',
              caseSensitive: false)
          .firstMatch(sql);
      if (match == null) {
        return {'ok': false, 'error': '无效的 DROP TABLE 语句'};
      }
      final tableName = match.group(1)!;
      _tables.remove(tableName);
      await _persist();
      return {'ok': true, 'rowsAffected': 0};
    }

    if (upper.startsWith('INSERT INTO')) {
      final match = RegExp(r'^INSERT\s+INTO\s+([a-zA-Z0-9_]+)',
              caseSensitive: false)
          .firstMatch(sql);
      if (match == null) {
        return {'ok': false, 'error': '无效的 INSERT 语句'};
      }
      final tableName = match.group(1)!;
      final table = _tables.putIfAbsent(tableName, () => []);

      // 解析列名列表 (若有)
      final colMatch = RegExp(r'\(([^)]+)\)\s*VALUES', caseSensitive: false)
          .firstMatch(sql);
      List<String>? cols;
      if (colMatch != null) {
        cols = colMatch
            .group(1)!
            .split(',')
            .map((c) => c.trim().replaceAll('`', '').replaceAll('"', ''))
            .toList();
      }

      // 提取 VALUES (...) 中的内容
      final valuesMatch = RegExp(r'VALUES\s*\((.*)\)', caseSensitive: false)
          .firstMatch(sql);
      List<dynamic> effectiveValues = params;
      if (params.isEmpty && valuesMatch != null) {
        effectiveValues = _parseValuesCsv(valuesMatch.group(1)!);
      }

      final row = <String, dynamic>{};
      if (cols != null && cols.length == effectiveValues.length) {
        for (int i = 0; i < cols.length; i++) {
          row[cols[i]] = effectiveValues[i];
        }
      } else {
        for (int i = 0; i < effectiveValues.length; i++) {
          row['col_${i + 1}'] = effectiveValues[i];
        }
      }

      table.add(row);
      await _persist();
      return {
        'ok': true,
        'rowsAffected': 1,
        'lastInsertId': table.length,
      };
    }

    if (upper.startsWith('DELETE FROM')) {
      final match = RegExp(r'^DELETE\s+FROM\s+([a-zA-Z0-9_]+)',
              caseSensitive: false)
          .firstMatch(sql);
      if (match == null) {
        return {'ok': false, 'error': '无效的 DELETE 语句'};
      }
      final tableName = match.group(1)!;
      final table = _tables[tableName];
      if (table == null) return {'ok': true, 'rowsAffected': 0};

      final whereClause = _extractWhereClause(sql);
      int deletedCount = 0;
      if (whereClause == null) {
        deletedCount = table.length;
        table.clear();
      } else {
        final initialLen = table.length;
        table.removeWhere((row) => _matchesWhere(row, whereClause, params));
        deletedCount = initialLen - table.length;
      }
      await _persist();
      return {'ok': true, 'rowsAffected': deletedCount};
    }

    if (upper.startsWith('UPDATE')) {
      final match =
          RegExp(r'^UPDATE\s+([a-zA-Z0-9_]+)\s+SET\s+(.+?)(?:\s+WHERE\s+(.+))?$',
                  caseSensitive: false)
              .firstMatch(sql);
      if (match == null) {
        return {'ok': false, 'error': '无效的 UPDATE 语句'};
      }
      final tableName = match.group(1)!;
      final setPart = match.group(2)!;
      final wherePart = match.group(3);

      final table = _tables[tableName];
      if (table == null) return {'ok': true, 'rowsAffected': 0};

      final setAssignments = _parseSetAssignments(setPart);
      int updatedCount = 0;

      // 提取参数分配
      int paramIdx = 0;
      final updatePairs = <String, dynamic>{};
      for (final entry in setAssignments.entries) {
        final col = entry.key;
        final rawVal = entry.value;
        if (rawVal == '?' && paramIdx < params.length) {
          updatePairs[col] = params[paramIdx++];
        } else {
          updatePairs[col] = _parseLiteral(rawVal);
        }
      }

      final remainingParams = params.sublist(paramIdx);

      for (final row in table) {
        if (wherePart == null ||
            _matchesWhere(row, wherePart, remainingParams)) {
          row.addAll(updatePairs);
          updatedCount++;
        }
      }
      await _persist();
      return {'ok': true, 'rowsAffected': updatedCount};
    }

    return {'ok': false, 'error': '不支持的 SQL 语句: $rawSql'};
  }

  Future<Map<String, dynamic>> query(
      String rawSql, List<dynamic> params) {
    final completer = Completer<Map<String, dynamic>>();
    _opQueue = _opQueue.whenComplete(() async {
      try {
        await _ensureLoaded();
        final res = await _queryInternal(rawSql, params);
        completer.complete(res);
      } catch (e) {
        completer.complete(
            {'ok': false, 'error': e.toString(), 'rows': <dynamic>[]});
      }
    });
    return completer.future;
  }

  Future<Map<String, dynamic>> _queryInternal(
      String rawSql, List<dynamic> params) async {
    final sql = _cleanSql(rawSql);
    final upper = sql.toUpperCase();
    if (!upper.startsWith('SELECT ')) {
      return {'ok': false, 'error': '无效的 SELECT 语句', 'rows': <dynamic>[]};
    }

    final fromIdx = upper.indexOf(' FROM ');
    if (fromIdx == -1) {
      return {
        'ok': false,
        'error': 'SELECT 语句缺少 FROM 子句',
        'rows': <dynamic>[]
      };
    }

    final fields = sql.substring(7, fromIdx).trim();
    final remaining = sql.substring(fromIdx + 6).trim();
    final upperRem = remaining.toUpperCase();

    // 寻找关键字位置
    final wherePos = upperRem.indexOf(' WHERE ');
    final orderPos = upperRem.indexOf(' ORDER BY ');
    final limitPos = upperRem.indexOf(' LIMIT ');
    final offsetPos = upperRem.indexOf(' OFFSET ');

    final positions = <MapEntry<String, int>>[
      if (wherePos != -1) MapEntry('WHERE', wherePos),
      if (orderPos != -1) MapEntry('ORDER BY', orderPos),
      if (limitPos != -1) MapEntry('LIMIT', limitPos),
      if (offsetPos != -1) MapEntry('OFFSET', offsetPos),
    ]..sort((a, b) => a.value.compareTo(b.value));

    String tableName;
    String? wherePart;
    String? orderPart;
    String? limitStr;
    String? offsetStr;

    if (positions.isEmpty) {
      tableName = remaining.trim();
    } else {
      tableName = remaining.substring(0, positions.first.value).trim();
      for (int i = 0; i < positions.length; i++) {
        final kw = positions[i].key;
        final start = positions[i].value + kw.length + 2; // ' ' + kw + ' '
        final end = (i + 1 < positions.length)
            ? positions[i + 1].value
            : remaining.length;
        final val = remaining.substring(start, end).trim();
        if (kw == 'WHERE') {
          wherePart = val;
        } else if (kw == 'ORDER BY') {
          orderPart = val;
        } else if (kw == 'LIMIT') {
          limitStr = val;
        } else if (kw == 'OFFSET') {
          offsetStr = val;
        }
      }
    }

    tableName = tableName.replaceAll('`', '').replaceAll('"', '');
    final table = _tables[tableName];
    if (table == null) {
      return {'ok': true, 'rows': <dynamic>[]};
    }

    var resultRows = List<Map<String, dynamic>>.from(table);

    // 过滤 WHERE
    final whereFilter = wherePart;
    if (whereFilter != null && whereFilter.isNotEmpty) {
      resultRows = resultRows
          .where((row) => _matchesWhere(row, whereFilter, params))
          .toList();
    }

    // 聚合函数 COUNT
    final countMatch = RegExp(r'^COUNT\s*\((.*?)\)(?:\s+AS\s+([a-zA-Z0-9_]+))?',
            caseSensitive: false)
        .firstMatch(fields);
    if (countMatch != null) {
      final alias = countMatch.group(2) ?? 'count';
      final count = resultRows.length;
      return {
        'ok': true,
        'rows': [
          {'count': count, alias: count}
        ]
      };
    }

    // 排序 ORDER BY
    if (orderPart != null && orderPart.isNotEmpty) {
      final isDesc = orderPart.toUpperCase().contains('DESC');
      final col = orderPart
          .replaceAll(
              RegExp(r'\s+(ASC|DESC)', caseSensitive: false), '')
          .trim()
          .replaceAll('`', '')
          .replaceAll('"', '');
      resultRows.sort((a, b) {
        final valA = a[col];
        final valB = b[col];
        if (valA == null && valB == null) return 0;
        if (valA == null) return isDesc ? 1 : -1;
        if (valB == null) return isDesc ? -1 : 1;
        final comp = Comparable.compare(
          valA is Comparable ? valA : valA.toString(),
          valB is Comparable ? valB : valB.toString(),
        );
        return isDesc ? -comp : comp;
      });
    }

    // 投影字段
    if (fields != '*') {
      final requestedCols = fields
          .split(',')
          .map((f) => f.trim().replaceAll('`', '').replaceAll('"', ''))
          .toList();
      resultRows = resultRows.map((row) {
        final projected = <String, dynamic>{};
        for (final col in requestedCols) {
          projected[col] = row[col];
        }
        return projected;
      }).toList();
    }

    // 分页 LIMIT / OFFSET
    if (offsetStr != null) {
      final offset = int.tryParse(offsetStr) ?? 0;
      if (offset < resultRows.length) {
        resultRows = resultRows.sublist(offset);
      } else {
        resultRows = [];
      }
    }
    if (limitStr != null) {
      final limit = int.tryParse(limitStr) ?? resultRows.length;
      if (limit < resultRows.length) {
        resultRows = resultRows.sublist(0, limit);
      }
    }

    return {'ok': true, 'rows': resultRows};
  }

  Future<Map<String, dynamic>> batch(
      List<Map<String, dynamic>> statements) async {
    int totalAffected = 0;
    for (final stmt in statements) {
      final sql = (stmt['sql'] ?? '').toString();
      final params = (stmt['params'] as List?) ?? [];
      final res = await execute(sql, params);
      if (res['ok'] == true) {
        totalAffected += (res['rowsAffected'] as num?)?.toInt() ?? 0;
      }
    }
    return {'ok': true, 'totalAffected': totalAffected};
  }

  String? _extractWhereClause(String sql) {
    final idx = sql.toUpperCase().indexOf('WHERE');
    if (idx != -1) {
      return sql.substring(idx + 5).trim();
    }
    return null;
  }

  bool _matchesWhere(
      Map<String, dynamic> row, String whereClause, List<dynamic> params) {
    final conditions = whereClause.split(RegExp(r'\s+AND\s+', caseSensitive: false));
    int paramIdx = 0;
    for (final cond in conditions) {
      if (!_evaluateCondition(row, cond.trim(), params, () => paramIdx++)) {
        return false;
      }
    }
    return true;
  }

  bool _evaluateCondition(Map<String, dynamic> row, String condition,
      List<dynamic> params, int Function() nextParamIdx) {
    final opMatch = RegExp(
            r'^(.*?)\s*(>=|<=|!=|<>|>|<|=|LIKE)\s*(.*)$',
            caseSensitive: false)
        .firstMatch(condition);
    if (opMatch == null) return true;

    final col = opMatch.group(1)!.trim().replaceAll('`', '').replaceAll('"', '');
    final op = opMatch.group(2)!.toUpperCase();
    final rightRaw = opMatch.group(3)!.trim();

    dynamic target;
    if (rightRaw == '?') {
      final idx = nextParamIdx();
      target = idx < params.length ? params[idx] : null;
    } else {
      target = _parseLiteral(rightRaw);
    }

    final val = row[col];
    if (op == '=') {
      return _compare(val, target) == 0;
    } else if (op == '!=' || op == '<>') {
      return _compare(val, target) != 0;
    } else if (op == '>') {
      return _compare(val, target) > 0;
    } else if (op == '>=') {
      return _compare(val, target) >= 0;
    } else if (op == '<') {
      return _compare(val, target) < 0;
    } else if (op == '<=') {
      return _compare(val, target) <= 0;
    } else if (op == 'LIKE') {
      if (val == null || target == null) return false;
      final patternStr = target
          .toString()
          .splitMapJoin(
            RegExp(r'[%_]'),
            onMatch: (m) => m[0] == '%' ? '.*' : '.',
            onNonMatch: (n) => RegExp.escape(n),
          );
      final pattern = RegExp('^$patternStr\$', caseSensitive: false);
      return pattern.hasMatch(val.toString());
    }
    return true;
  }

  static int _compare(dynamic a, dynamic b) {
    if (a == null && b == null) return 0;
    if (a == null) return -1;
    if (b == null) return 1;
    if (a is num && b is num) return a.compareTo(b);
    return a.toString().compareTo(b.toString());
  }

  static String _cleanSql(String raw) {
    var s = raw.replaceAll(RegExp(r'--[^\r\n]*'), ' ');
    s = s.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), ' ');
    return s.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static Map<String, String> _parseSetAssignments(String setPart) {
    final map = <String, String>{};
    final items = _parseCsv(setPart);
    for (final item in items) {
      final eqIdx = item.indexOf('=');
      if (eqIdx != -1) {
        final col = item
            .substring(0, eqIdx)
            .trim()
            .replaceAll('`', '')
            .replaceAll('"', '');
        final val = item.substring(eqIdx + 1).trim();
        map[col] = val;
      }
    }
    return map;
  }

  static List<String> _parseCsv(String csv) {
    final list = <String>[];
    final buffer = StringBuffer();
    bool inQuote = false;
    String quoteChar = '';
    for (int i = 0; i < csv.length; i++) {
      final ch = csv[i];
      if (inQuote) {
        if (ch == quoteChar) {
          inQuote = false;
        }
        buffer.write(ch);
      } else {
        if (ch == "'" || ch == '"') {
          inQuote = true;
          quoteChar = ch;
          buffer.write(ch);
        } else if (ch == ',') {
          list.add(buffer.toString().trim());
          buffer.clear();
        } else {
          buffer.write(ch);
        }
      }
    }
    if (buffer.isNotEmpty) {
      list.add(buffer.toString().trim());
    }
    return list;
  }

  static List<dynamic> _parseValuesCsv(String csv) {
    final rawList = _parseCsv(csv);
    return rawList.map((s) => _parseLiteral(s)).toList();
  }

  static dynamic _parseLiteral(String s) {
    if (s.isEmpty) return null;
    final lower = s.toLowerCase();
    if (lower == 'null') return null;
    if (lower == 'true') return true;
    if (lower == 'false') return false;
    if (int.tryParse(s) != null) return int.parse(s);
    if (double.tryParse(s) != null) return double.parse(s);
    if ((s.startsWith("'") && s.endsWith("'")) ||
        (s.startsWith('"') && s.endsWith('"'))) {
      if (s.length >= 2) return s.substring(1, s.length - 1);
      return '';
    }
    return s;
  }
}
