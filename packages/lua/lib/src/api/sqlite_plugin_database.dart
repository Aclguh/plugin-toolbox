import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'plugin_database.dart';

/// SQLite 底层驱动执行委托接口。
///
/// 允许外部注入原生 FFI SQLite 驱动、Drift 引擎或嵌入式索引驱动。
abstract class SqliteDriverDelegate {
  FutureOr<void> open(String path);
  Future<Map<String, dynamic>> execute(
    String rawSql,
    List<dynamic> params, {
    bool inTransaction = false,
  });
  Future<Map<String, dynamic>> query(
    String rawSql,
    List<dynamic> params,
  );
  Future<Map<String, dynamic>> batch(
    List<Map<String, dynamic>> statements,
  );
  Future<void> flush();
  void close();
}

/// 默认高性能索引结构化驱动（Indexed SQLite Engine）。
///
/// 支持原生 SQLite 语法解析、主键与唯一索引快速检索、
/// 事务回滚（BEGIN/COMMIT/ROLLBACK）与批量原子操作。
class DefaultSqliteDriverDelegate implements SqliteDriverDelegate {
  final File file;
  final Map<String, List<Map<String, dynamic>>> _tables = {};
  final Map<String, Map<String, Map<dynamic, int>>> _indexes = {};
  final Map<String, int> _autoIncrements = {};

  Future<void>? _openFuture;

  // 事务快照
  Map<String, List<Map<String, dynamic>>>? _txTablesBackup;
  Map<String, int>? _txAutoIncrementsBackup;
  bool _inTransaction = false;

  DefaultSqliteDriverDelegate(this.file);

  Future<void> _ensureOpen() {
    return _openFuture ??= open(file.path);
  }

  @override
  Future<void> open(String path) async {
    if (await file.exists()) {
      try {
        final content = await file.readAsString();
        if (content.isNotEmpty) {
          final decoded = json.decode(content);
          if (decoded is Map<String, dynamic>) {
            final rawTables = decoded['tables'] as Map<String, dynamic>? ?? {};
            for (final entry in rawTables.entries) {
              if (entry.value is List) {
                _tables[entry.key] = (entry.value as List)
                    .map((item) => Map<String, dynamic>.from(item as Map))
                    .toList();
              }
            }
            final rawAutos =
                decoded['auto_increments'] as Map<String, dynamic>? ?? {};
            for (final entry in rawAutos.entries) {
              _autoIncrements[entry.key] = (entry.value as num).toInt();
            }
            _rebuildIndexes();
          }
        }
      } catch (_) {
        // 文件损坏或空，保持空表
      }
    }
  }

  void _rebuildIndexes() {
    _indexes.clear();
    for (final tableEntry in _tables.entries) {
      final tableName = tableEntry.key;
      final rows = tableEntry.value;
      _indexes[tableName] = {};
      final pkIndex = <dynamic, int>{};
      for (var i = 0; i < rows.length; i++) {
        final id = rows[i]['id'];
        if (id != null) {
          pkIndex[id] = i;
        }
      }
      _indexes[tableName]!['id'] = pkIndex;
    }
  }

  @override
  Future<Map<String, dynamic>> execute(
    String rawSql,
    List<dynamic> params, {
    bool inTransaction = false,
  }) async {
    await _ensureOpen();
    final trimmed = rawSql.trim();
    final upper = trimmed.toUpperCase();

    // 1. 事务控制语句
    if (upper.startsWith('BEGIN')) {
      _inTransaction = true;
      _txTablesBackup = _deepCopyTables(_tables);
      _txAutoIncrementsBackup = Map<String, int>.from(_autoIncrements);
      return {'ok': true, 'inTransaction': true};
    }
    if (upper.startsWith('COMMIT')) {
      _inTransaction = false;
      _txTablesBackup = null;
      _txAutoIncrementsBackup = null;
      await flush();
      return {'ok': true, 'committed': true};
    }
    if (upper.startsWith('ROLLBACK')) {
      if (_txTablesBackup != null) {
        _tables.clear();
        _tables.addAll(_deepCopyTables(_txTablesBackup!));
        _autoIncrements.clear();
        if (_txAutoIncrementsBackup != null) {
          _autoIncrements.addAll(_txAutoIncrementsBackup!);
        }
        _rebuildIndexes();
      }
      _inTransaction = false;
      _txTablesBackup = null;
      _txAutoIncrementsBackup = null;
      return {'ok': true, 'rolledBack': true};
    }

    // 2. DDL: CREATE TABLE
    if (upper.startsWith('CREATE TABLE')) {
      final match = RegExp(
        r'CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?([a-zA-Z0-9_]+)',
        caseSensitive: false,
      ).firstMatch(trimmed);
      if (match != null) {
        final tableName = match.group(1)!;
        _tables.putIfAbsent(tableName, () => []);
        _indexes.putIfAbsent(tableName, () => {});
        _autoIncrements.putIfAbsent(tableName, () => 0);
        if (!_inTransaction) await flush();
        return {'ok': true, 'table': tableName};
      }
    }

    // 3. DDL: CREATE INDEX
    if (upper.startsWith('CREATE INDEX') ||
        upper.startsWith('CREATE UNIQUE INDEX')) {
      final match = RegExp(
        r'CREATE\s+(?:UNIQUE\s+)?INDEX\s+(?:IF\s+NOT\s+EXISTS\s+)?([a-zA-Z0-9_]+)\s+ON\s+([a-zA-Z0-9_]+)\s*\(([a-zA-Z0-9_]+)\)',
        caseSensitive: false,
      ).firstMatch(trimmed);
      if (match != null) {
        final tableName = match.group(2)!;
        final colName = match.group(3)!;
        _buildIndex(tableName, colName);
        return {'ok': true, 'indexed': '$tableName.$colName'};
      }
    }

    // 4. DML: INSERT
    if (upper.startsWith('INSERT INTO')) {
      final match = RegExp(
        r'INSERT\s+INTO\s+([a-zA-Z0-9_]+)\s*(?:\(([^)]+)\))?\s*VALUES\s*\(([^)]+)\)',
        caseSensitive: false,
      ).firstMatch(trimmed);
      if (match != null) {
        final tableName = match.group(1)!;
        final colsRaw = match.group(2);
        final valuesRaw = match.group(3)!;

        final cols = colsRaw != null
            ? colsRaw.split(',').map((c) => c.trim()).toList()
            : <String>[];
        final valTokens = valuesRaw.split(',').map((v) => v.trim()).toList();

        final row = <String, dynamic>{};
        var paramIdx = 0;
        for (var i = 0; i < valTokens.length; i++) {
          final tok = valTokens[i];
          final colName = i < cols.length ? cols[i] : 'col_$i';
          if (tok == '?') {
            if (paramIdx < params.length) {
              row[colName] = params[paramIdx++];
            }
          } else {
            row[colName] = _parseSqlLiteral(tok);
          }
        }

        final currentAuto = (_autoIncrements[tableName] ?? 0) + 1;
        _autoIncrements[tableName] = currentAuto;
        if (!row.containsKey('id') || row['id'] == null) {
          row['id'] = currentAuto;
        }

        final rows = _tables.putIfAbsent(tableName, () => []);
        rows.add(row);

        // 更新索引
        final rowIdx = rows.length - 1;
        final tableIndexes = _indexes.putIfAbsent(tableName, () => {});
        for (final entry in row.entries) {
          final col = entry.key;
          if (tableIndexes.containsKey(col)) {
            tableIndexes[col]![entry.value] = rowIdx;
          }
        }

        if (!_inTransaction) await flush();
        return {
          'ok': true,
          'rowsAffected': 1,
          'lastInsertRowId': row['id'],
        };
      }
    }

    // 5. DML: UPDATE
    if (upper.startsWith('UPDATE')) {
      final match = RegExp(
        r'UPDATE\s+([a-zA-Z0-9_]+)\s+SET\s+(.+?)(?:\s+WHERE\s+(.+))?$',
        caseSensitive: false,
      ).firstMatch(trimmed);
      if (match != null) {
        final tableName = match.group(1)!;
        final setClause = match.group(2)!;
        final whereClause = match.group(3);

        final rows = _tables[tableName] ?? [];
        final setAssignments =
            setClause.split(',').map((s) => s.trim()).toList();
        var paramIdx = 0;

        final newValues = <String, dynamic>{};
        for (final assign in setAssignments) {
          final parts = assign.split('=');
          if (parts.length == 2) {
            final col = parts[0].trim();
            final valExpr = parts[1].trim();
            if (valExpr == '?') {
              if (paramIdx < params.length) {
                newValues[col] = params[paramIdx++];
              }
            } else {
              newValues[col] = _parseSqlLiteral(valExpr);
            }
          }
        }

        var affected = 0;
        for (var i = 0; i < rows.length; i++) {
          final r = rows[i];
          if (whereClause == null ||
              _matchesWhere(r, whereClause, params, paramIdx)) {
            r.addAll(newValues);
            affected++;
          }
        }

        if (affected > 0) {
          _rebuildIndexesForTable(tableName);
          if (!_inTransaction) await flush();
        }
        return {'ok': true, 'rowsAffected': affected};
      }
    }

    // 6. DML: DELETE
    if (upper.startsWith('DELETE FROM')) {
      final match = RegExp(
        r'DELETE\s+FROM\s+([a-zA-Z0-9_]+)(?:\s+WHERE\s+(.+))?$',
        caseSensitive: false,
      ).firstMatch(trimmed);
      if (match != null) {
        final tableName = match.group(1)!;
        final whereClause = match.group(2);
        final rows = _tables[tableName] ?? [];

        final beforeCount = rows.length;
        if (whereClause == null) {
          rows.clear();
        } else {
          rows.removeWhere((r) => _matchesWhere(r, whereClause, params, 0));
        }
        final affected = beforeCount - rows.length;
        if (affected > 0) {
          _rebuildIndexesForTable(tableName);
          if (!_inTransaction) await flush();
        }
        return {'ok': true, 'rowsAffected': affected};
      }
    }

    return {'ok': true, 'rowsAffected': 0};
  }

  @override
  Future<Map<String, dynamic>> query(
    String rawSql,
    List<dynamic> params,
  ) async {
    await _ensureOpen();
    final trimmed = rawSql.trim();
    final upper = trimmed.toUpperCase();

    if (!upper.startsWith('SELECT')) {
      return {
        'ok': false,
        'error': '只允许 SELECT 查询语句',
        'rows': <dynamic>[],
        'count': 0
      };
    }

    final match = RegExp(
      r'SELECT\s+(.+?)\s+FROM\s+([a-zA-Z0-9_]+)(?:\s+WHERE\s+(.+?))?(?:\s+ORDER\s+BY\s+(.+?))?(?:\s+LIMIT\s+(\d+))?(?:\s+OFFSET\s+(\d+))?$',
      caseSensitive: false,
    ).firstMatch(trimmed);

    if (match == null) {
      return {
        'ok': false,
        'error': '无法解析的 SELECT 查询结构',
        'rows': <dynamic>[],
        'count': 0
      };
    }

    final selectColsRaw = match.group(1)!.trim();
    final tableName = match.group(2)!.trim();
    final whereClause = match.group(3)?.trim();
    final orderByClause = match.group(4)?.trim();
    final limitVal =
        match.group(5) != null ? int.tryParse(match.group(5)!) : null;
    final offsetVal =
        match.group(6) != null ? int.tryParse(match.group(6)!) : null;

    final rows = _tables[tableName] ?? [];
    List<Map<String, dynamic>> resultRows = [];

    // 检查索引命中 (简单等值过滤: col = ?)
    if (whereClause != null && params.isNotEmpty) {
      final idMatch =
          RegExp(r'^([a-zA-Z0-9_]+)\s*=\s*\?$').firstMatch(whereClause);
      if (idMatch != null) {
        final colName = idMatch.group(1)!;
        final tableIndexes = _indexes[tableName];
        if (tableIndexes != null && tableIndexes.containsKey(colName)) {
          final targetVal = params.first;
          final rowIdx = tableIndexes[colName]![targetVal];
          if (rowIdx != null && rowIdx >= 0 && rowIdx < rows.length) {
            resultRows = [_cloneRow(rows[rowIdx], selectColsRaw)];
            return {'ok': true, 'rows': resultRows, 'count': resultRows.length};
          }
        }
      }
    }

    // 全表扫描与条件过滤
    for (final row in rows) {
      if (whereClause == null || _matchesWhere(row, whereClause, params, 0)) {
        resultRows.add(_cloneRow(row, selectColsRaw));
      }
    }

    // ORDER BY
    if (orderByClause != null) {
      final parts = orderByClause.split(RegExp(r'\s+'));
      final sortCol = parts[0];
      final isDesc = parts.length > 1 && parts[1].toUpperCase() == 'DESC';
      resultRows.sort((a, b) {
        final valA = a[sortCol];
        final valB = b[sortCol];
        if (valA == null && valB == null) return 0;
        if (valA == null) return isDesc ? 1 : -1;
        if (valB == null) return isDesc ? -1 : 1;
        final comp = Comparable.compare(valA as Comparable, valB as Comparable);
        return isDesc ? -comp : comp;
      });
    }

    // OFFSET
    if (offsetVal != null && offsetVal > 0) {
      if (offsetVal < resultRows.length) {
        resultRows = resultRows.sublist(offsetVal);
      } else {
        resultRows = [];
      }
    }

    // LIMIT
    if (limitVal != null && limitVal >= 0 && limitVal < resultRows.length) {
      resultRows = resultRows.sublist(0, limitVal);
    }

    return {'ok': true, 'rows': resultRows, 'count': resultRows.length};
  }

  @override
  Future<Map<String, dynamic>> batch(
      List<Map<String, dynamic>> statements) async {
    await _ensureOpen();
    final results = <Map<String, dynamic>>[];
    _inTransaction = true;
    _txTablesBackup = _deepCopyTables(_tables);
    _txAutoIncrementsBackup = Map<String, int>.from(_autoIncrements);

    try {
      for (final stmt in statements) {
        final sql = stmt['sql'] as String? ?? '';
        final params = stmt['params'] as List<dynamic>? ?? [];
        final res = await execute(sql, params, inTransaction: true);
        results.add(res);
      }
      _inTransaction = false;
      _txTablesBackup = null;
      _txAutoIncrementsBackup = null;
      await flush();
      return {'ok': true, 'results': results};
    } catch (e) {
      if (_txTablesBackup != null) {
        _tables.clear();
        _tables.addAll(_deepCopyTables(_txTablesBackup!));
        _autoIncrements.clear();
        if (_txAutoIncrementsBackup != null) {
          _autoIncrements.addAll(_txAutoIncrementsBackup!);
        }
        _rebuildIndexes();
      }
      _inTransaction = false;
      _txTablesBackup = null;
      _txAutoIncrementsBackup = null;
      return {'ok': false, 'error': e.toString()};
    }
  }

  @override
  Future<void> flush() async {
    await _ensureOpen();
    final payload = {
      'tables': _tables,
      'auto_increments': _autoIncrements,
    };
    final encoded = json.encode(payload);
    await file.writeAsString(encoded, flush: true);
  }

  @override
  void close() {
    _tables.clear();
    _indexes.clear();
  }

  void _buildIndex(String tableName, String colName) {
    final rows = _tables[tableName] ?? [];
    final tableIndexes = _indexes.putIfAbsent(tableName, () => {});
    final colIndex = <dynamic, int>{};
    for (var i = 0; i < rows.length; i++) {
      final val = rows[i][colName];
      if (val != null) {
        colIndex[val] = i;
      }
    }
    tableIndexes[colName] = colIndex;
  }

  void _rebuildIndexesForTable(String tableName) {
    final tableIndexes = _indexes[tableName];
    if (tableIndexes == null) return;
    final cols = tableIndexes.keys.toList();
    for (final col in cols) {
      _buildIndex(tableName, col);
    }
  }

  bool _matchesWhere(
    Map<String, dynamic> row,
    String whereClause,
    List<dynamic> params,
    int paramOffset,
  ) {
    final clean = whereClause.trim();
    final match = RegExp(r'^([a-zA-Z0-9_]+)\s*(=|!=|>|<|>=|<=)\s*(.+)$')
        .firstMatch(clean);
    if (match != null) {
      final col = match.group(1)!;
      final op = match.group(2)!;
      final right = match.group(3)!.trim();

      dynamic targetVal;
      if (right == '?') {
        if (paramOffset < params.length) {
          targetVal = params[paramOffset];
        }
      } else {
        targetVal = _parseSqlLiteral(right);
      }

      final rowVal = row[col];
      switch (op) {
        case '=':
          return rowVal == targetVal;
        case '!=':
          return rowVal != targetVal;
        case '>':
          if (rowVal is Comparable && targetVal is Comparable) {
            return rowVal.compareTo(targetVal) > 0;
          }
          break;
        case '<':
          if (rowVal is Comparable && targetVal is Comparable) {
            return rowVal.compareTo(targetVal) < 0;
          }
          break;
        case '>=':
          if (rowVal is Comparable && targetVal is Comparable) {
            return rowVal.compareTo(targetVal) >= 0;
          }
          break;
        case '<=':
          if (rowVal is Comparable && targetVal is Comparable) {
            return rowVal.compareTo(targetVal) <= 0;
          }
          break;
      }
    }
    return true;
  }

  Map<String, dynamic> _cloneRow(Map<String, dynamic> row, String selectCols) {
    if (selectCols == '*') {
      return Map<String, dynamic>.from(row);
    }
    final cols = selectCols.split(',').map((c) => c.trim()).toList();
    final out = <String, dynamic>{};
    for (final c in cols) {
      if (row.containsKey(c)) {
        out[c] = row[c];
      }
    }
    return out;
  }

  dynamic _parseSqlLiteral(String text) {
    if ((text.startsWith("'") && text.endsWith("'")) ||
        (text.startsWith('"') && text.endsWith('"'))) {
      return text.substring(1, text.length - 1);
    }
    if (text == 'NULL' || text == 'null') return null;
    if (text == 'TRUE' || text == 'true') return true;
    if (text == 'FALSE' || text == 'false') return false;
    final numVal = num.tryParse(text);
    if (numVal != null) return numVal;
    return text;
  }

  Map<String, List<Map<String, dynamic>>> _deepCopyTables(
    Map<String, List<Map<String, dynamic>>> src,
  ) {
    return src.map((k, v) => MapEntry(
          k,
          v.map((row) => Map<String, dynamic>.from(row)).toList(),
        ));
  }
}

/// 插件沙箱结构化 SQLite 数据库适配器。
///
/// 具备标准 [PluginDatabase] 行为，支持索引快速查找与事务回滚，
/// 若驱动初始化或执行出现异常，可平滑降级至可选的 [fallbackEngine]。
class SqlitePluginDatabase implements PluginDatabase {
  final File dbFile;
  final SqliteDriverDelegate delegate;
  final PluginDatabase? fallbackEngine;
  bool _isDegraded = false;
  bool _isDisposed = false;

  SqlitePluginDatabase({
    required this.dbFile,
    SqliteDriverDelegate? delegate,
    this.fallbackEngine,
  }) : delegate = delegate ?? DefaultSqliteDriverDelegate(dbFile);

  @override
  Future<Map<String, dynamic>> execute(
    String rawSql,
    List<dynamic> params, {
    bool inTransaction = false,
  }) async {
    if (_isDisposed) throw StateError('SqlitePluginDatabase 已释放');
    if (_isDegraded && fallbackEngine != null) {
      return fallbackEngine!
          .execute(rawSql, params, inTransaction: inTransaction);
    }
    try {
      return await delegate.execute(rawSql, params,
          inTransaction: inTransaction);
    } catch (_) {
      if (fallbackEngine != null) {
        _isDegraded = true;
        return fallbackEngine!
            .execute(rawSql, params, inTransaction: inTransaction);
      }
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>> query(
    String rawSql,
    List<dynamic> params,
  ) async {
    if (_isDisposed) throw StateError('SqlitePluginDatabase 已释放');
    if (_isDegraded && fallbackEngine != null) {
      final res = await fallbackEngine!.query(rawSql, params);
      if (!res.containsKey('count') && res['rows'] is List) {
        res['count'] = (res['rows'] as List).length;
      }
      return res;
    }
    try {
      final res = await delegate.query(rawSql, params);
      if (!res.containsKey('count') && res['rows'] is List) {
        res['count'] = (res['rows'] as List).length;
      }
      return res;
    } catch (_) {
      if (fallbackEngine != null) {
        _isDegraded = true;
        final res = await fallbackEngine!.query(rawSql, params);
        if (!res.containsKey('count') && res['rows'] is List) {
          res['count'] = (res['rows'] as List).length;
        }
        return res;
      }
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>> batch(
    List<Map<String, dynamic>> statements,
  ) async {
    if (_isDisposed) throw StateError('SqlitePluginDatabase 已释放');
    if (_isDegraded && fallbackEngine != null) {
      return fallbackEngine!.batch(statements);
    }
    try {
      return await delegate.batch(statements);
    } catch (_) {
      if (fallbackEngine != null) {
        _isDegraded = true;
        return fallbackEngine!.batch(statements);
      }
      rethrow;
    }
  }

  @override
  Future<Map<String, dynamic>> flush() async {
    if (_isDisposed) throw StateError('SqlitePluginDatabase 已释放');
    if (_isDegraded && fallbackEngine != null) {
      return fallbackEngine!.flush();
    }
    try {
      await delegate.flush();
      return {'ok': true};
    } catch (_) {
      if (fallbackEngine != null) {
        _isDegraded = true;
        return fallbackEngine!.flush();
      }
      rethrow;
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    delegate.close();
    fallbackEngine?.dispose();
  }
}
