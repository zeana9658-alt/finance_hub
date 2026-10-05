import 'package:finance_hub/data/database/app_database.dart';
import 'package:finance_hub/domain/services/backup_service.dart';
import 'package:sqflite/sqflite.dart' as sqflite;

/// [BackupStore] 的 SQLite 实现。
class BackupStoreImpl implements BackupStore {
  BackupStoreImpl(this._database);

  final AppDatabase _database;

  @override
  Future<List<Map<String, Object?>>> selectAll(
    String table, {
    Set<String> exclude = const <String>{},
  }) async {
    final db = await _database.open();
    final rows = await db.query(table);
    if (exclude.isEmpty) {
      return rows;
    }
    return rows
        .map(
          (row) => Map<String, Object?>.of(row)
            ..removeWhere((key, value) => exclude.contains(key)),
        )
        .toList(growable: false);
  }

  @override
  Future<Map<String, String>> readSettings() async {
    final db = await _database.open();
    final rows = await db.query('app_settings');
    final map = <String, String>{};
    for (final row in rows) {
      final key = row['key'] as String?;
      if (key == null) {
        continue;
      }
      map[key] = '${row['value'] ?? ''}';
    }
    return map;
  }

  @override
  Future<void> writeSettings(Map<String, String> values) async {
    final db = await _database.open();
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final entry in values.entries) {
      await db.insert(
        'app_settings',
        <String, Object?>{
          'key': entry.key,
          'value': entry.value,
          'updated_at': now,
        },
        conflictAlgorithm: sqflite.ConflictAlgorithm.replace,
      );
    }
  }

  @override
  Future<int> countActiveTransactions() async {
    final db = await _database.open();
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM transactions WHERE deleted_at IS NULL',
    );
    return rows.isEmpty ? 0 : (rows.first['c'] as int? ?? 0);
  }

  @override
  Future<int> softDeleteAllTransactions() async {
    final db = await _database.open();
    final now = DateTime.now().millisecondsSinceEpoch;
    return db.update(
      'transactions',
      <String, Object?>{'deleted_at': now, 'updated_at': now},
      where: 'deleted_at IS NULL',
    );
  }

  @override
  Future<int> insertRowsIgnore(
    String table,
    List<Map<String, Object?>> rows,
  ) async {
    if (rows.isEmpty) {
      return 0;
    }
    final db = await _database.open();
    return db.transaction<int>((txn) async {
      final before = await _count(txn, table);
      for (final row in rows) {
        await txn.insert(
          table,
          row,
          conflictAlgorithm: sqflite.ConflictAlgorithm.ignore,
        );
      }
      final after = await _count(txn, table);
      return after - before;
    });
  }

  @override
  Future<int> insertRulesSkippingExistingNames(
    List<Map<String, Object?>> rows,
  ) async {
    if (rows.isEmpty) {
      return 0;
    }
    final db = await _database.open();
    return db.transaction<int>((txn) async {
      var inserted = 0;
      for (final row in rows) {
        final name = row['name'] as String?;
        if (name == null || name.isEmpty) {
          continue;
        }
        final existing = await txn.query(
          'category_rules',
          columns: <String>['id'],
          where: 'name = ?',
          whereArgs: <Object?>[name],
          limit: 1,
        );
        if (existing.isNotEmpty) {
          continue;
        }
        // 去掉备份里的旧主键，让本机重新分配
        await txn.insert(
          'category_rules',
          Map<String, Object?>.of(row)..remove('id'),
        );
        inserted++;
      }
      return inserted;
    });
  }

  @override
  Future<int> insertRow(String table, Map<String, Object?> row) async {
    final db = await _database.open();
    return db.insert(table, row);
  }

  @override
  Future<void> upsertBudget(Map<String, Object?> row) async {
    final db = await _database.open();
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      // budgets 上有 (category_id, period) WHERE is_active = 1 的部分唯一索引，
      // 先删掉同键的旧记录再插入，避免唯一约束冲突。
      await txn.delete(
        'budgets',
        where: 'category_id IS ? AND period = ?',
        whereArgs: <Object?>[row['category_id'], row['period']],
      );
      await txn.insert('budgets', <String, Object?>{
        ...row,
        'created_at': row['created_at'] ?? now,
        'updated_at': now,
      });
    });
  }

  @override
  Future<int?> findCategoryId({required String name, int? parentId}) async {
    final db = await _database.open();
    final rows = parentId == null
        ? await db.query(
            'categories',
            columns: <String>['id'],
            where: 'name = ? AND parent_id IS NULL',
            whereArgs: <Object?>[name],
            limit: 1,
          )
        : await db.query(
            'categories',
            columns: <String>['id'],
            where: 'name = ? AND parent_id = ?',
            whereArgs: <Object?>[name, parentId],
            limit: 1,
          );
    if (rows.isEmpty) {
      return null;
    }
    return rows.first['id'] as int?;
  }

  @override
  Future<List<Map<String, Object?>>> selectCategoryIndex() async {
    final db = await _database.open();
    return db.query(
      'categories',
      columns: <String>['id', 'name', 'parent_id', 'level'],
    );
  }

  Future<int> _count(sqflite.DatabaseExecutor db, String table) async {
    final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM $table');
    return rows.isEmpty ? 0 : (rows.first['c'] as int? ?? 0);
  }
}
