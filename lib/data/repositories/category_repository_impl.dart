import 'package:finance_hub/data/database/app_database.dart';
import 'package:finance_hub/domain/entities/category.dart';
import 'package:finance_hub/domain/repositories/category_repository.dart';

/// [CategoryRepository] 的 SQLite 实现。
class CategoryRepositoryImpl implements CategoryRepository {
  CategoryRepositoryImpl(this._database);

  final AppDatabase _database;

  static const String _t = 'categories';

  @override
  Future<List<Category>> loadAll() async {
    final db = await _database.open();
    final rows = await db.query(
      _t,
      where: 'is_active = 1',
      orderBy: 'level, sort_order, id',
    );
    return rows.map(Category.fromMap).toList(growable: false);
  }

  @override
  Future<List<Category>> topLevel({CategoryKind? kind}) async {
    final db = await _database.open();
    final rows = await db.query(
      _t,
      where: kind == null
          ? 'is_active = 1 AND level = 1'
          : 'is_active = 1 AND level = 1 AND kind = ?',
      whereArgs: kind == null ? null : <Object?>[kind.code],
      orderBy: 'sort_order, id',
    );
    return rows.map(Category.fromMap).toList(growable: false);
  }

  @override
  Future<List<Category>> childrenOf(int parentId) async {
    final db = await _database.open();
    final rows = await db.query(
      _t,
      where: 'is_active = 1 AND parent_id = ?',
      whereArgs: <Object?>[parentId],
      orderBy: 'sort_order, id',
    );
    return rows.map(Category.fromMap).toList(growable: false);
  }

  @override
  Future<Map<int, String>> nameMap() async {
    final db = await _database.open();
    final rows = await db.query(
      _t,
      columns: <String>['id', 'name'],
      where: 'is_active = 1',
    );
    final map = <int, String>{};
    for (final row in rows) {
      final id = row['id'] as int?;
      final name = row['name'] as String?;
      if (id != null && name != null) {
        map[id] = name;
      }
    }
    return map;
  }

  @override
  Future<int> create(Category category) async {
    final db = await _database.open();
    final now = DateTime.now().millisecondsSinceEpoch;
    return db.insert(_t, <String, Object?>{
      ...category.toMap(),
      'created_at': now,
      'updated_at': now,
    }..remove('id'));
  }

  @override
  Future<void> update(Category category) async {
    final id = category.id;
    if (id == null) {
      return;
    }
    final db = await _database.open();
    await db.update(
      _t,
      <String, Object?>{
        'name': category.name,
        'parent_id': category.parentId,
        'level': category.level,
        'kind': category.kind.code,
        'icon': category.icon,
        'color': category.color,
        'sort_order': category.sortOrder,
        'is_active': category.isActive ? 1 : 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  @override
  Future<void> deactivate(int id) async {
    final db = await _database.open();
    await db.update(
      _t,
      <String, Object?>{
        'is_active': 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  @override
  Future<bool> topLevelNameExists(String name) async {
    final db = await _database.open();
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM $_t WHERE level = 1 AND name = ?',
      <Object?>[name],
    );
    final count = rows.isEmpty ? 0 : (rows.first['c'] as int? ?? 0);
    return count > 0;
  }
}
