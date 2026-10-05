import 'package:finance_hub/data/database/app_database.dart';
import 'package:finance_hub/domain/entities/budget.dart';
import 'package:finance_hub/domain/repositories/budget_repository.dart';

/// [BudgetRepository] 的 SQLite 实现。
class BudgetRepositoryImpl implements BudgetRepository {
  BudgetRepositoryImpl(this._database);

  final AppDatabase _database;

  static const String _t = 'budgets';

  @override
  Future<List<Budget>> loadActive() async {
    final db = await _database.open();
    final rows = await db.query(
      _t,
      where: 'is_active = 1',
      orderBy: 'category_id IS NULL DESC, category_id, subcategory_id',
    );
    return rows.map(Budget.fromMap).toList(growable: false);
  }

  @override
  Future<int> upsert(Budget budget) async {
    final db = await _database.open();
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = budget.id;

    if (id != null) {
      await db.update(
        _t,
        <String, Object?>{
          ...budget.toInsertMap(),
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: <Object?>[id],
      );
      return id;
    }

    // 表上有 `ux_budgets_category_period`（category_id + period，仅 is_active = 1）
    // 的部分唯一索引。用户对同一分类同一周期再设一次预算时，
    // 直接 insert 会撞唯一约束 —— 因此先移除同键的旧记录再插入，
    // 语义上等价于「覆盖该分类本期的预算」。
    return db.transaction<int>((txn) async {
      await txn.delete(
        _t,
        where: 'category_id IS ? AND period = ? AND is_active = 1',
        whereArgs: <Object?>[budget.categoryId, budget.period.code],
      );
      return txn.insert(_t, <String, Object?>{
        ...budget.toInsertMap(),
        'created_at': now,
        'updated_at': now,
      });
    });
  }

  @override
  Future<void> remove(int id) async {
    final db = await _database.open();
    await db.delete(_t, where: 'id = ?', whereArgs: <Object?>[id]);
  }

  @override
  Future<void> setActive(int id, bool active) async {
    final db = await _database.open();
    await db.update(
      _t,
      <String, Object?>{
        'is_active': active ? 1 : 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }
}
