import 'package:finance_hub/core/utils/date_range.dart';
import 'package:finance_hub/core/utils/text_utils.dart';
import 'package:finance_hub/data/database/app_database.dart';
import 'package:finance_hub/domain/entities/normalized_transaction.dart';
import 'package:finance_hub/domain/enums/bill_source.dart';
import 'package:finance_hub/domain/enums/category_source.dart';
import 'package:finance_hub/domain/repositories/transaction_repository.dart';
import 'package:finance_hub/domain/services/duplicate_detector.dart';
import 'package:sqflite/sqflite.dart' as sqflite;

/// [TransactionRepository] 的 SQLite 实现。
class TransactionRepositoryImpl implements TransactionRepository {
  TransactionRepositoryImpl(this._database);

  final AppDatabase _database;

  static const String _table = 'transactions';

  @override
  Future<int> insertAll(List<NormalizedTransaction> transactions) async {
    if (transactions.isEmpty) {
      return 0;
    }
    final db = await _database.open();

    return db.transaction<int>((txn) async {
      final before = await _count(txn);
      for (final transaction in transactions) {
        // INSERT OR IGNORE：即使预览阶段判重有漏，
        // 部分唯一索引 ux_transactions_unique_key 仍会兜底拦下。
        await txn.insert(
          _table,
          transaction.toInsertMap(),
          conflictAlgorithm: sqflite.ConflictAlgorithm.ignore,
        );
      }
      final after = await _count(txn);
      return after - before;
    });
  }

  @override
  Future<Set<String>> existingUniqueKeys({
    required int fromMillis,
    required int toMillis,
  }) async {
    final db = await _database.open();
    final rows = await db.query(
      _table,
      columns: <String>['unique_key'],
      where:
          'deleted_at IS NULL AND transaction_time >= ? AND transaction_time < ?',
      whereArgs: <Object?>[fromMillis, toMillis],
    );
    return rows
        .map((row) => row['unique_key'] as String?)
        .whereType<String>()
        .toSet();
  }

  @override
  Future<List<TransactionProbe>> existingProbes({
    required int fromMillis,
    required int toMillis,
  }) async {
    final db = await _database.open();
    final rows = await db.query(
      _table,
      columns: <String>[
        'source',
        'transaction_time',
        'amount_cents',
        'merchant',
      ],
      where:
          'deleted_at IS NULL AND transaction_time >= ? AND transaction_time < ?',
      whereArgs: <Object?>[fromMillis, toMillis],
    );

    final probes = <TransactionProbe>[];
    for (final row in rows) {
      final source = BillSource.fromCode(row['source'] as String?);
      if (source == null) {
        continue;
      }
      final time = DateTime.fromMillisecondsSinceEpoch(
        row['transaction_time'] as int? ?? 0,
      );
      probes.add(
        TransactionProbe(
          baseKey: '${dayKey(time)}|${row['amount_cents'] as int? ?? 0}|'
              '${merchantKeyOf(row['merchant'] as String? ?? '')}',
          source: source,
        ),
      );
    }
    return probes;
  }

  @override
  Future<List<NormalizedTransaction>> findByRange({
    required int fromMillis,
    required int toMillis,
    int? limit,
    int offset = 0,
  }) async {
    final db = await _database.open();
    final rows = await db.query(
      _table,
      where:
          'deleted_at IS NULL AND transaction_time >= ? AND transaction_time < ?',
      whereArgs: <Object?>[fromMillis, toMillis],
      orderBy: 'transaction_time DESC, id DESC',
      limit: limit,
      offset: limit == null ? null : offset,
    );
    return rows.map(NormalizedTransaction.fromMap).toList(growable: false);
  }

  @override
  Future<int> count({bool includeDeleted = false}) async {
    final db = await _database.open();
    return _count(db, includeDeleted: includeDeleted);
  }

  @override
  Future<void> softDelete(int id) async {
    final db = await _database.open();
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.update(
      _table,
      <String, Object?>{'deleted_at': now, 'updated_at': now},
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  @override
  Future<void> restore(int id) async {
    final db = await _database.open();
    await db.update(
      _table,
      <String, Object?>{
        'deleted_at': null,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  @override
  Future<void> updateCategory({
    required int id,
    required int? categoryId,
    required int? subcategoryId,
    required bool markAsManual,
  }) async {
    final db = await _database.open();
    await db.update(
      _table,
      <String, Object?>{
        'category_id': categoryId,
        'subcategory_id': subcategoryId,
        if (markAsManual) 'category_source': CategorySource.manual.code,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<int> _count(
    sqflite.DatabaseExecutor db, {
    bool includeDeleted = false,
  }) async {
    final result = await db.rawQuery(
      includeDeleted
          ? 'SELECT COUNT(*) AS c FROM $_table'
          : 'SELECT COUNT(*) AS c FROM $_table WHERE deleted_at IS NULL',
    );
    return sqflite.Sqflite.firstIntValue(result) ?? 0;
  }
}
