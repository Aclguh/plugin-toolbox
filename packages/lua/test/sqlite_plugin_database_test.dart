import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_toolbox_lua/plugin_toolbox_lua.dart';

void main() {
  group('SqlitePluginDatabase 结构化存储驱动测试', () {
    late Directory tempDir;
    late File dbFile;
    late SqlitePluginDatabase database;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('sqlite_db_test_');
      dbFile = File('${tempDir.path}/test_plugin.db');
      database = SqlitePluginDatabase(dbFile: dbFile);
    });

    tearDown(() async {
      database.dispose();
      try {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      } catch (_) {}
    });

    test('DDL 与 DML: 建表、主键递增写入与批量插入', () async {
      final createRes = await database.execute(
        'CREATE TABLE IF NOT EXISTS notes (id INTEGER PRIMARY KEY, title TEXT, content TEXT)',
        [],
      );
      expect(createRes['ok'], isTrue);
      expect(createRes['table'], 'notes');

      final insert1 = await database.execute(
        'INSERT INTO notes (title, content) VALUES (?, ?)',
        ['买菜清单', '西红柿、鸡蛋、牛奶'],
      );
      expect(insert1['ok'], isTrue);
      expect(insert1['rowsAffected'], 1);
      expect(insert1['lastInsertRowId'], 1);

      final insert2 = await database.execute(
        'INSERT INTO notes (title, content) VALUES (?, ?)',
        ['开发计划', '重构沙箱数据库引擎'],
      );
      expect(insert2['ok'], isTrue);
      expect(insert2['rowsAffected'], 1);
      expect(insert2['lastInsertRowId'], 2);

      final queryRes = await database.query('SELECT * FROM notes', []);
      expect(queryRes['ok'], isTrue);
      expect(queryRes['count'], 2);
      final rows = queryRes['rows'] as List;
      expect(rows[0]['title'], '买菜清单');
      expect(rows[1]['title'], '开发计划');
    });

    test('SELECT: WHERE 等值/区间过滤、ORDER BY 与 LIMIT/OFFSET 分页', () async {
      await database.execute(
          'CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, age INT)',
          []);
      await database.execute(
          'INSERT INTO users (name, age) VALUES (?, ?)', ['Alice', 20]);
      await database
          .execute('INSERT INTO users (name, age) VALUES (?, ?)', ['Bob', 25]);
      await database.execute(
          'INSERT INTO users (name, age) VALUES (?, ?)', ['Charlie', 30]);
      await database.execute(
          'INSERT INTO users (name, age) VALUES (?, ?)', ['David', 35]);

      // WHERE 等值过滤
      final resEq = await database
          .query('SELECT name, age FROM users WHERE name = ?', ['Bob']);
      expect(resEq['count'], 1);
      expect(resEq['rows'][0]['name'], 'Bob');
      expect(resEq['rows'][0]['age'], 25);

      // WHERE 范围过滤
      final resRange =
          await database.query('SELECT name FROM users WHERE age > ?', [22]);
      expect(resRange['count'], 3);

      // ORDER BY DESC
      final resOrder = await database
          .query('SELECT name, age FROM users ORDER BY age DESC', []);
      expect(resOrder['rows'][0]['name'], 'David');
      expect(resOrder['rows'][3]['name'], 'Alice');

      // LIMIT 与 OFFSET
      final resPage = await database.query(
          'SELECT name FROM users ORDER BY age ASC LIMIT 2 OFFSET 1', []);
      expect(resPage['count'], 2);
      expect(resPage['rows'][0]['name'], 'Bob');
      expect(resPage['rows'][1]['name'], 'Charlie');
    });

    test('UPDATE 与 DELETE: 条件更新与行数统计', () async {
      await database
          .execute('CREATE TABLE tasks (id INTEGER, status TEXT)', []);
      await database.execute(
          'INSERT INTO tasks (id, status) VALUES (?, ?)', [1, 'pending']);
      await database.execute(
          'INSERT INTO tasks (id, status) VALUES (?, ?)', [2, 'pending']);

      final updateRes = await database
          .execute('UPDATE tasks SET status = ? WHERE id = ?', ['done', 1]);
      expect(updateRes['rowsAffected'], 1);

      final q1 =
          await database.query('SELECT status FROM tasks WHERE id = ?', [1]);
      expect(q1['rows'][0]['status'], 'done');

      final deleteRes =
          await database.execute('DELETE FROM tasks WHERE id = ?', [2]);
      expect(deleteRes['rowsAffected'], 1);

      final q2 = await database.query('SELECT * FROM tasks', []);
      expect(q2['count'], 1);
    });

    test('事务原子性: BEGIN / ROLLBACK 回滚与 COMMIT 提交', () async {
      await database
          .execute('CREATE TABLE ledger (id INTEGER, amount INT)', []);
      await database
          .execute('INSERT INTO ledger (id, amount) VALUES (?, ?)', [1, 100]);

      // 1. 回滚测试
      await database.execute('BEGIN TRANSACTION', []);
      await database
          .execute('INSERT INTO ledger (id, amount) VALUES (?, ?)', [2, 200]);
      await database
          .execute('UPDATE ledger SET amount = ? WHERE id = ?', [999, 1]);
      await database.execute('ROLLBACK', []);

      final checkRollback = await database.query('SELECT * FROM ledger', []);
      expect(checkRollback['count'], 1);
      expect(checkRollback['rows'][0]['amount'], 100);

      // 2. 提交测试
      await database.execute('BEGIN TRANSACTION', []);
      await database
          .execute('INSERT INTO ledger (id, amount) VALUES (?, ?)', [3, 300]);
      await database.execute('COMMIT', []);

      final checkCommit = await database.query('SELECT * FROM ledger', []);
      expect(checkCommit['count'], 2);
    });

    test('batch 批量原子执行', () async {
      await database.execute('CREATE TABLE tags (name TEXT)', []);
      final batchRes = await database.batch([
        {
          'sql': 'INSERT INTO tags (name) VALUES (?)',
          'params': ['flutter']
        },
        {
          'sql': 'INSERT INTO tags (name) VALUES (?)',
          'params': ['lua']
        },
        {
          'sql': 'INSERT INTO tags (name) VALUES (?)',
          'params': ['sqlite']
        },
      ]);
      expect(batchRes['ok'], isTrue);
      expect((batchRes['results'] as List).length, 3);

      final countQ = await database.query('SELECT * FROM tags', []);
      expect(countQ['count'], 3);
    });

    test('持久化与重新打开: flush 后数据不丢失', () async {
      await database.execute('CREATE TABLE settings (k TEXT, v TEXT)', []);
      await database.execute(
          'INSERT INTO settings (k, v) VALUES (?, ?)', ['theme', 'dark']);
      await database.flush();
      database.dispose();

      // 重新实例化
      final reloaded = SqlitePluginDatabase(dbFile: dbFile);
      // 等待重新加载
      final res =
          await reloaded.query('SELECT v FROM settings WHERE k = ?', ['theme']);
      expect(res['count'], 1);
      expect(res['rows'][0]['v'], 'dark');
      reloaded.dispose();
    });

    test('异常平滑降级: 驱动出错时透明转接 fallbackEngine', () async {
      final fallbackFile = File('${tempDir.path}/fallback.db');
      final fallbackEngine = SandboxDatabaseEngine(dbFile: fallbackFile);

      // 使用一个会抛出未处理异常的 Mock 委托
      final throwingDb = SqlitePluginDatabase(
        dbFile: dbFile,
        delegate: _AlwaysThrowDriverDelegate(),
        fallbackEngine: fallbackEngine,
      );

      final res = await throwingDb.execute(
        'CREATE TABLE test_fb (id INTEGER PRIMARY KEY, msg TEXT)',
        [],
      );
      expect(res['ok'], isTrue);

      final insertRes = await throwingDb.execute(
        'INSERT INTO test_fb (id, msg) VALUES (1, "fallback_ok")',
        [],
      );
      expect(insertRes['ok'], isTrue);

      final queryRes = await throwingDb.query('SELECT * FROM test_fb', []);
      expect(queryRes['ok'], isTrue);
      expect(queryRes['count'], 1);

      throwingDb.dispose();
    });
  });
}

class _AlwaysThrowDriverDelegate implements SqliteDriverDelegate {
  @override
  void open(String path) {}

  @override
  Future<Map<String, dynamic>> execute(String rawSql, List<dynamic> params,
      {bool inTransaction = false}) {
    throw Exception('Native driver error');
  }

  @override
  Future<Map<String, dynamic>> query(String rawSql, List<dynamic> params) {
    throw Exception('Native driver query error');
  }

  @override
  Future<Map<String, dynamic>> batch(List<Map<String, dynamic>> statements) {
    throw Exception('Native driver batch error');
  }

  @override
  Future<void> flush() async {}

  @override
  void close() {}
}
