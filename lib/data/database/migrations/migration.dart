import 'package:sqflite/sqflite.dart';

/// 数据库迁移单元。
///
/// **铁律**：已发布的 Migration **永不修改**，只追加新文件。
/// 修改历史迁移会让老用户与新用户的 schema 分叉（见 docs/DATABASE.md §7）。
abstract class Migration {
  const Migration();

  /// 目标版本号，必须唯一且递增。
  int get version;

  /// 人类可读名称，会写入 `schema_migrations` 台账。
  String get name;

  /// 执行升级。会被包在一个事务里。
  Future<void> up(DatabaseExecutor db);
}
