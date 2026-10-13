import 'dart:io';

/// 插件沙箱结构化数据库统一抽象契约。
///
/// 约束纯 Dart JSON 回退引擎与原生 SQLite / Drift 高性能驱动的统一行为，
/// 支持未来在大型存储或重度事务场景下透明切换驱动实现。
abstract class PluginDatabase {
  /// 执行写操作 SQL（INSERT, UPDATE, DELETE, CREATE 等）
  Future<Map<String, dynamic>> execute(
    String rawSql,
    List<dynamic> params, {
    bool inTransaction = false,
  });

  /// 执行读操作 SQL（SELECT）
  Future<Map<String, dynamic>> query(
    String rawSql,
    List<dynamic> params,
  );

  /// 批量执行多条 SQL 语句
  Future<Map<String, dynamic>> batch(
    List<Map<String, dynamic>> statements,
  );

  /// 将内存缓冲区或事务变更持久化写入磁盘介质
  Future<Map<String, dynamic>> flush();

  /// 释放数据库连接与相关系统资源
  void dispose();
}

/// 数据库驱动工厂类型定义
typedef PluginDatabaseFactory = PluginDatabase Function(File dbFile);
