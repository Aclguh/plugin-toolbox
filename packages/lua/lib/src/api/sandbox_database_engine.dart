import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'plugin_database.dart';

/// 纯 Dart 轻量沙箱结构化存储引擎（JSON 回退实现）。
///
/// 以单 JSON 文件承载全部表数据，写操作经串行操作队列排队执行，
/// 脏数据防抖合并落盘；作为 [PluginDatabase] 默认的开箱即用轻量实现。
import 'package:logger/logger.dart';
import 'package:plugin_toolbox_core/plugin_toolbox_core.dart';

class SandboxDatabaseEngine implements PluginDatabase {
  final File dbFile;
  final EventBus? eventBus;
  final Logger? logger;
  final String? pluginId;

  Map<String, List<Map<String, dynamic>>> _tables = {};
  Future<void>? _loadFuture;
  Future<dynamic> _opQueue = Future.value();
  bool _isDirty = false;
  Timer? _debounceTimer;

  SandboxDatabaseEngine({
    required this.dbFile,
    this.eventBus,
    this.logger,
    this.pluginId,
  });

  Future<void> _ensureLoaded() {
    return _loadFuture ??= _doLoad();
  }

  Future<void> _doLoad() async {
    Object? primaryError;
    final tag = pluginId != null ? '[$pluginId]' : '[Database]';

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
          return;
        }
        primaryError = const FormatException('数据库文件根节点不是有效 Map');
      } catch (e, st) {
        primaryError = e;
        logger?.w('$tag 数据库主文件损坏: ${dbFile.path}', error: e, stackTrace: st);
      }
    }

    final bakFile = File('${dbFile.path}.bak');
    if (await bakFile.exists()) {
      try {
        final content = await bakFile.readAsString();
        final decoded = json.decode(content);
        if (decoded is Map<String, dynamic>) {
          _tables = decoded.map((k, v) => MapEntry(
                k,
                (v as List)
                    .map((item) => Map<String, dynamic>.from(item as Map))
                    .toList(),
              ));
          logger?.i('$tag 成功从备份恢复数据库: ${bakFile.path}');
          eventBus?.fire(StorageCorruptionEvent(
            namespace: pluginId ?? 'database',
            filePath: dbFile.path,
            reason: '主数据库损坏 ($primaryError)，已从备份恢复',
            recoveredFromBackup: true,
          ));
          return;
        }
      } catch (e, st) {
        logger?.w('$tag 数据库备份文件解析失败: ${bakFile.path}',
            error: e, stackTrace: st);
      }
    }

    if (primaryError != null) {
      logger?.e('$tag 数据库主文件与备份均已损坏，正在重置为空库: ${dbFile.path}');
      eventBus?.fire(StorageCorruptionEvent(
        namespace: pluginId ?? 'database',
        filePath: dbFile.path,
        reason: '数据库主文件与全部备份损坏且无法恢复 ($primaryError)，已重置为空',
        recoveredFromBackup: false,
      ));
    }

    _tables = {};
  }

  void _schedulePersist() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 50), () {
      flush();
    });
  }

  Future<void> _persist() async {
    try {
      if (!await dbFile.parent.exists()) {
        await dbFile.parent.create(recursive: true);
      }
      final payload = json.encode(_tables);
      final tempFile = File('${dbFile.path}.tmp');
      await tempFile.writeAsString(payload, flush: true);

      final bakFile = File('${dbFile.path}.bak');
      if (await dbFile.exists()) {
        try {
          if (await bakFile.exists()) await bakFile.delete();
          await dbFile.copy(bakFile.path);
        } catch (_) {}
      }
      // rename 本身即原子替换主文件，绝不预删主文件：
      // 先 delete 再 rename 会在两者之间留下崩溃窗口，窗口期主库整体丢失。
      try {
        await tempFile.rename(dbFile.path);
      } on FileSystemException {
        // 部分平台 rename 不覆盖既有目标，回退为先删后换
        try {
          await dbFile.delete();
        } catch (_) {}
        await tempFile.rename(dbFile.path);
      }
    } catch (_) {}
  }

  @override
  Future<Map<String, dynamic>> flush() {
    final completer = Completer<Map<String, dynamic>>();
    _opQueue = _opQueue.whenComplete(() async {
      _debounceTimer?.cancel();
      _debounceTimer = null;
      if (!_isDirty) {
        completer.complete({'ok': true});
        return;
      }
      try {
        await _persist();
        _isDirty = false;
        completer.complete({'ok': true});
      } catch (e) {
        completer.complete({'ok': false, 'error': e.toString()});
      }
    });
    return completer.future;
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    if (_isDirty) {
      try {
        if (!dbFile.parent.existsSync()) {
          dbFile.parent.createSync(recursive: true);
        }
        final tempFile = File('${dbFile.path}.tmp');
        tempFile.writeAsStringSync(json.encode(_tables), flush: true);
        final bakFile = File('${dbFile.path}.bak');
        if (dbFile.existsSync()) {
          try {
            if (bakFile.existsSync()) bakFile.deleteSync();
            dbFile.copySync(bakFile.path);
          } catch (_) {}
        }
        // 与 _persist 同理：rename 原子覆盖，不预删主文件
        try {
          tempFile.renameSync(dbFile.path);
        } on FileSystemException {
          try {
            dbFile.deleteSync();
          } catch (_) {}
          tempFile.renameSync(dbFile.path);
        }
        _isDirty = false;
      } catch (_) {}
    }
  }

  @override
  Future<Map<String, dynamic>> execute(String rawSql, List<dynamic> params,
      {bool autoPersist = true, bool inTransaction = false}) {
    final completer = Completer<Map<String, dynamic>>();
    _opQueue = _opQueue.whenComplete(() async {
      try {
        await _ensureLoaded();
        final res =
            await _executeInternal(rawSql, params, autoPersist: autoPersist);
        completer.complete(res);
      } catch (e) {
        completer.complete({'ok': false, 'error': e.toString()});
      }
    });
    return completer.future;
  }

  Future<Map<String, dynamic>> _executeInternal(
      String rawSql, List<dynamic> params,
      {bool autoPersist = true}) async {
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
      _isDirty = true;
      if (autoPersist) _schedulePersist();
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
      _isDirty = true;
      if (autoPersist) _schedulePersist();
      return {'ok': true, 'rowsAffected': 0};
    }

    if (upper.startsWith('INSERT INTO')) {
      final match =
          RegExp(r'^INSERT\s+INTO\s+([a-zA-Z0-9_]+)', caseSensitive: false)
              .firstMatch(sql);
      if (match == null) {
        return {'ok': false, 'error': '无效的 INSERT 语句'};
      }
      final tableName = match.group(1)!;
      final table = _tables.putIfAbsent(tableName, () => []);

      // 解析列名列表 (若有)
      final colMatch =
          RegExp(r'\(([^)]+)\)\s*VALUES', caseSensitive: false).firstMatch(sql);
      List<String>? cols;
      if (colMatch != null) {
        cols = colMatch
            .group(1)!
            .split(',')
            .map((c) => c.trim().replaceAll('`', '').replaceAll('"', ''))
            .toList();
      }

      // 提取 VALUES (...) 中的内容
      final valuesMatch =
          RegExp(r'VALUES\s*\((.*)\)', caseSensitive: false).firstMatch(sql);
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
      _isDirty = true;
      if (autoPersist) _schedulePersist();
      return {
        'ok': true,
        'rowsAffected': 1,
        'lastInsertId': table.length,
      };
    }

    if (upper.startsWith('DELETE FROM')) {
      final match =
          RegExp(r'^DELETE\s+FROM\s+([a-zA-Z0-9_]+)', caseSensitive: false)
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
      if (deletedCount > 0) {
        _isDirty = true;
        if (autoPersist) _schedulePersist();
      }
      return {'ok': true, 'rowsAffected': deletedCount};
    }

    if (upper.startsWith('UPDATE')) {
      final match = RegExp(
              r'^UPDATE\s+([a-zA-Z0-9_]+)\s+SET\s+(.+?)(?:\s+WHERE\s+(.+))?$',
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
      if (updatedCount > 0) {
        _isDirty = true;
        if (autoPersist) _schedulePersist();
      }
      return {'ok': true, 'rowsAffected': updatedCount};
    }

    return {'ok': false, 'error': '不支持的 SQL 语句: $rawSql'};
  }

  @override
  Future<Map<String, dynamic>> query(String rawSql, List<dynamic> params) {
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
      return {'ok': false, 'error': 'SELECT 语句缺少 FROM 子句', 'rows': <dynamic>[]};
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
          .replaceAll(RegExp(r'\s+(ASC|DESC)', caseSensitive: false), '')
          .trim()
          .replaceAll('`', '')
          .replaceAll('"', '');
      resultRows.sort((a, b) {
        final valA = a[col];
        final valB = b[col];
        if (valA == null && valB == null) return 0;
        if (valA == null) return isDesc ? 1 : -1;
        if (valB == null) return isDesc ? -1 : 1;
        final int comp;
        if (valA is num && valB is num) {
          comp = valA.compareTo(valB);
        } else if (valA is Comparable && valA.runtimeType == valB.runtimeType) {
          comp = (valA as dynamic).compareTo(valB);
        } else {
          comp = valA.toString().compareTo(valB.toString());
        }
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

  @override
  Future<Map<String, dynamic>> batch(List<Map<String, dynamic>> statements) {
    final completer = Completer<Map<String, dynamic>>();
    _opQueue = _opQueue.whenComplete(() async {
      try {
        await _ensureLoaded();
        int totalAffected = 0;
        for (final stmt in statements) {
          final sql = (stmt['sql'] ?? '').toString();
          final params = (stmt['params'] as List?) ?? [];
          final res = await _executeInternal(sql, params, autoPersist: false);
          if (res['ok'] == true) {
            totalAffected += (res['rowsAffected'] as num?)?.toInt() ?? 0;
          }
        }
        if (_isDirty) {
          _debounceTimer?.cancel();
          _debounceTimer = null;
          await _persist();
          _isDirty = false;
        }
        completer.complete({'ok': true, 'totalAffected': totalAffected});
      } catch (e) {
        completer.complete({'ok': false, 'error': e.toString()});
      }
    });
    return completer.future;
  }

  String? _extractWhereClause(String sql) {
    final idx = sql.toUpperCase().indexOf('WHERE');
    if (idx != -1) {
      return sql.substring(idx + 5).trim();
    }
    return null;
  }

  static List<String> _splitWhereConditions(String whereClause) {
    final list = <String>[];
    final buffer = StringBuffer();
    bool inQuote = false;
    String quoteChar = '';
    int parenDepth = 0;

    int i = 0;
    while (i < whereClause.length) {
      final ch = whereClause[i];
      if (inQuote) {
        buffer.write(ch);
        if (ch == quoteChar) {
          if (i + 1 < whereClause.length && whereClause[i + 1] == quoteChar) {
            buffer.write(whereClause[i + 1]);
            i++;
          } else {
            inQuote = false;
          }
        }
        i++;
      } else {
        if (ch == "'" || ch == '"') {
          inQuote = true;
          quoteChar = ch;
          buffer.write(ch);
          i++;
        } else if (ch == '(') {
          parenDepth++;
          buffer.write(ch);
          i++;
        } else if (ch == ')') {
          if (parenDepth > 0) parenDepth--;
          buffer.write(ch);
          i++;
        } else if (parenDepth == 0 &&
            (i == 0 || RegExp(r'\s').hasMatch(whereClause[i - 1])) &&
            whereClause.substring(i).toUpperCase().startsWith('AND') &&
            (i + 3 >= whereClause.length ||
                RegExp(r'\s').hasMatch(whereClause[i + 3]))) {
          final trimmed = buffer.toString().trim();
          if (trimmed.isNotEmpty) {
            list.add(trimmed);
          }
          buffer.clear();
          i += 3;
        } else {
          buffer.write(ch);
          i++;
        }
      }
    }
    final remaining = buffer.toString().trim();
    if (remaining.isNotEmpty) {
      list.add(remaining);
    }
    return list;
  }

  bool _matchesWhere(
      Map<String, dynamic> row, String whereClause, List<dynamic> params) {
    final conditions = _splitWhereConditions(whereClause);
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
    final opMatch = RegExp(r'^(.*?)\s*(>=|<=|!=|<>|>|<|=|LIKE)\s*(.*)$',
            caseSensitive: false)
        .firstMatch(condition);
    if (opMatch == null) return true;

    final col =
        opMatch.group(1)!.trim().replaceAll('`', '').replaceAll('"', '');
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
      final patternStr = target.toString().splitMapJoin(
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
    final buffer = StringBuffer();
    bool inQuote = false;
    String quoteChar = '';
    int i = 0;
    while (i < raw.length) {
      final ch = raw[i];
      if (inQuote) {
        buffer.write(ch);
        if (ch == quoteChar) {
          if (i + 1 < raw.length && raw[i + 1] == quoteChar) {
            buffer.write(raw[i + 1]);
            i++;
          } else {
            inQuote = false;
          }
        }
        i++;
      } else {
        if (ch == "'" || ch == '"') {
          inQuote = true;
          quoteChar = ch;
          buffer.write(ch);
          i++;
        } else if (ch == '-' && i + 1 < raw.length && raw[i + 1] == '-') {
          i += 2;
          while (i < raw.length && raw[i] != '\n' && raw[i] != '\r') {
            i++;
          }
          buffer.write(' ');
        } else if (ch == '/' && i + 1 < raw.length && raw[i + 1] == '*') {
          i += 2;
          while (i + 1 < raw.length && !(raw[i] == '*' && raw[i + 1] == '/')) {
            i++;
          }
          i += 2;
          buffer.write(' ');
        } else {
          buffer.write(ch);
          i++;
        }
      }
    }
    return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
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
    if (lower == 'null' || lower == 'nil') return null;
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

/// 纯 Dart JSON 结构化存储引擎别名，供适配层显式表达降级语义
typedef JsonFallbackDatabase = SandboxDatabaseEngine;
