import 'dart:io';

import 'package:finance_hub/data/database/app_database.dart';
import 'package:finance_hub/data/repositories/transaction_repository_impl.dart';
import 'package:finance_hub/domain/entities/normalized_transaction.dart';
import 'package:finance_hub/domain/enums/bill_source.dart';
import 'package:finance_hub/domain/enums/transaction_type.dart';
import 'package:finance_hub/domain/services/transaction_fingerprint.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  // 桌面/测试环境必须用 FFI 工厂
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tempDir;
  late AppDatabase database;
  late TransactionRepositoryImpl repository;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('finance_hub_test_');
    database = AppDatabase(
      databasePath: p.join(tempDir.path, 'test.sqlite'),
    );
    await database.open();
    repository = TransactionRepositoryImpl(database);
  });

  tearDown(() async {
    await database.close();
  });

  NormalizedTransaction tx({
    String? externalId = 'TEST-MIG-0001',
    int amountCents = 2800,
    String merchant = '示例咖啡',
    DateTime? time,
  }) {
    final when = time ?? DateTime(2026, 6, 12, 8, 30);
    return NormalizedTransaction(
      source: BillSource.wechat,
      sourceTransactionId: externalId,
      uniqueKey: TransactionFingerprint.compute(
        source: BillSource.wechat,
        externalId: externalId,
        transactionTime: when,
        amountCents: amountCents,
        merchant: merchant,
        description: '拿铁',
        paymentMethod: '零钱',
      ),
      transactionTime: when,
      transactionTimeRaw: '',
      transactionType: TransactionType.expense,
      transactionTypeRaw: '',
      amountCents: amountCents,
      merchant: merchant,
      description: '拿铁',
      paymentMethod: '零钱',
      createdAt: when,
      updatedAt: when,
    );
  }

  group('迁移', () {
    test('迁移台账记录了每个版本', () async {
      final db = await database.open();
      final rows = await db.query('schema_migrations', orderBy: 'version');
      expect(rows.length, 2);
      expect(rows[0]['version'], 1);
      expect(rows[0]['name'], 'initial_schema');
      expect(rows[1]['version'], 2);
      expect(rows[1]['name'], 'seed_categories_and_rules');
    });

    test('schema 版本等于最大迁移版本', () {
      expect(AppDatabase.schemaVersion, 2);
    });

    test('所有表都已创建', () async {
      final db = await database.open();
      final rows = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name",
      );
      final names = rows.map((row) => row['name'] as String).toSet();
      expect(
        names,
        containsAll(<String>[
          'transactions', 'categories', 'category_rules', 'merchant_rules',
          'accounts', 'budgets', 'financial_goals', 'import_records',
          'app_settings', 'backup_records', 'schema_migrations',
        ]),
      );
    });

    test('种子分类：17 个一级分类 + 二级分类', () async {
      final db = await database.open();
      final topRows = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM categories WHERE level = 1',
      );
      expect(topRows.first['c'], 17);

      final names = (await db.query('categories', columns: <String>['name']))
          .map((row) => row['name'] as String)
          .toSet();
      expect(
        names,
        containsAll(<String>['餐饮', '交通', '购物', '娱乐', '居住', '工资', '其他']),
      );

      final subRows = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM categories WHERE level = 2',
      );
      expect(subRows.first['c'], greaterThan(30));
    });

    test('内置规则已写入且 is_builtin = 1', () async {
      final db = await database.open();
      final rows = await db.query('category_rules');
      expect(rows.length, greaterThan(10));
      for (final row in rows) {
        expect(row['is_builtin'], 1);
        expect(row['enabled'], 1);
      }
    });

    test('重复打开不会重复执行迁移', () async {
      await database.close();
      final reopened = AppDatabase(
        databasePath: p.join(tempDir.path, 'test.sqlite'),
      );
      await reopened.open();
      final db = await reopened.open();
      final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM categories');
      expect(rows.first['c'], greaterThan(40));
      final topRows = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM categories WHERE level = 1',
      );
      expect(topRows.first['c'], 17, reason: '不应重复插入种子分类');
      await reopened.close();
    });
  });

  group('TransactionRepository', () {
    test('批量写入并统计', () async {
      final inserted = await repository.insertAll(<NormalizedTransaction>[
        tx(externalId: 'TEST-MIG-0001'),
        tx(externalId: 'TEST-MIG-0002', amountCents: 3300),
      ]);
      expect(inserted, 2);
      expect(await repository.count(), 2);
    });

    test('重复写入被唯一索引拦下（INSERT OR IGNORE）', () async {
      await repository.insertAll(<NormalizedTransaction>[tx()]);
      final again = await repository.insertAll(<NormalizedTransaction>[tx()]);
      expect(again, 0, reason: '相同 unique_key 不应重复写入');
      expect(await repository.count(), 1);
    });

    test('软删除后可重新导入同一笔（部分唯一索引）', () async {
      await repository.insertAll(<NormalizedTransaction>[tx()]);
      final rows = await repository.findByRange(
        fromMillis: DateTime(2026, 1, 1).millisecondsSinceEpoch,
        toMillis: DateTime(2027, 1, 1).millisecondsSinceEpoch,
      );
      expect(rows.length, 1);
      await repository.softDelete(rows.first.id!);
      expect(await repository.count(), 0);
      expect(await repository.count(includeDeleted: true), 1);

      // 软删除后重新导入应成功
      final reinserted =
          await repository.insertAll(<NormalizedTransaction>[tx()]);
      expect(reinserted, 1);
    });

    test('撤销软删除', () async {
      await repository.insertAll(<NormalizedTransaction>[tx()]);
      final rows = await repository.findByRange(
        fromMillis: DateTime(2026, 1, 1).millisecondsSinceEpoch,
        toMillis: DateTime(2027, 1, 1).millisecondsSinceEpoch,
      );
      final id = rows.first.id!;
      await repository.softDelete(id);
      expect(await repository.count(), 0);
      await repository.restore(id);
      expect(await repository.count(), 1);
    });

    test('existingUniqueKeys 只返回区间内未删除的记录', () async {
      await repository.insertAll(<NormalizedTransaction>[
        tx(externalId: 'A', time: DateTime(2026, 6, 1)),
        tx(externalId: 'B', time: DateTime(2026, 8, 1)),
      ]);
      final keys = await repository.existingUniqueKeys(
        fromMillis: DateTime(2026, 5, 1).millisecondsSinceEpoch,
        toMillis: DateTime(2026, 7, 1).millisecondsSinceEpoch,
      );
      expect(keys.length, 1);
      expect(keys.first, contains('A'));
    });

    test('existingProbes 供跨平台提示使用', () async {
      await repository.insertAll(<NormalizedTransaction>[
        tx(externalId: 'A', amountCents: 3800, merchant: '示例餐厅'),
      ]);
      final probes = await repository.existingProbes(
        fromMillis: DateTime(2026, 6, 1).millisecondsSinceEpoch,
        toMillis: DateTime(2026, 7, 1).millisecondsSinceEpoch,
      );
      expect(probes.length, 1);
      expect(probes.first.baseKey, contains('3800'));
    });

    test('updateCategory 标记为 manual 后不被重跑覆盖', () async {
      await repository.insertAll(<NormalizedTransaction>[tx()]);
      final rows = await repository.findByRange(
        fromMillis: DateTime(2026, 1, 1).millisecondsSinceEpoch,
        toMillis: DateTime(2027, 1, 1).millisecondsSinceEpoch,
      );
      final id = rows.first.id!;
      await repository.updateCategory(
        id: id,
        categoryId: 1,
        subcategoryId: 2,
        markAsManual: true,
      );
      final updated = (await repository.findByRange(
        fromMillis: DateTime(2026, 1, 1).millisecondsSinceEpoch,
        toMillis: DateTime(2027, 1, 1).millisecondsSinceEpoch,
      ))
          .first;
      expect(updated.categoryId, 1);
      expect(updated.subcategoryId, 2);
      expect(updated.isCategoryLocked, isTrue);
    });
  });

  group('金额完整性', () {
    test('库中所有金额均为整数分，无浮点残留', () async {
      await repository.insertAll(<NormalizedTransaction>[
        tx(externalId: 'A', amountCents: 3852),
        tx(externalId: 'B', amountCents: 7),
      ]);
      final db = await database.open();
      final rows = await db.rawQuery('SELECT amount_cents FROM transactions');
      for (final row in rows) {
        expect(row['amount_cents'], isA<int>());
      }
    });

    test('负数金额被 CHECK 约束拒绝', () async {
      final db = await database.open();
      await expectLater(
        db.insert('transactions', <String, Object?>{
          'source': 'wechat',
          'unique_key': 'src:wechat:NEGATIVE',
          'transaction_time': DateTime(2026, 6, 1).millisecondsSinceEpoch,
          'transaction_type': 'expense',
          'amount_cents': -100,
          'created_at': 0,
          'updated_at': 0,
        }),
        throwsA(anything),
      );
    });
  });
}
