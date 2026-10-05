import 'dart:convert';
import 'dart:io';

import 'package:finance_hub/data/database/app_database.dart';
import 'package:finance_hub/data/repositories/backup_store_impl.dart';
import 'package:finance_hub/data/repositories/category_repository_impl.dart';
import 'package:finance_hub/data/repositories/transaction_repository_impl.dart';
import 'package:finance_hub/domain/entities/normalized_transaction.dart';
import 'package:finance_hub/domain/enums/bill_source.dart';
import 'package:finance_hub/domain/enums/transaction_type.dart';
import 'package:finance_hub/domain/services/backup_service.dart';
import 'package:finance_hub/domain/services/transaction_fingerprint.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 备份导出 / 解析 / 预览 / 恢复的集成测试。
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tempDir;
  late AppDatabase database;
  late TransactionRepositoryImpl transactions;
  late CategoryRepositoryImpl categories;
  late BackupStoreImpl store;
  late BackupService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('finance_hub_backup_');
    database = AppDatabase(databasePath: p.join(tempDir.path, 'test.sqlite'));
    await database.open();
    transactions = TransactionRepositoryImpl(database);
    categories = CategoryRepositoryImpl(database);
    store = BackupStoreImpl(database);
    service = BackupService(store);
  });

  tearDown(() async {
    await database.close();
  });

  var seq = 0;

  Future<void> insertTx({
    required DateTime time,
    required int amountCents,
    String merchant = '示例商户',
    int? categoryId,
  }) async {
    seq++;
    await transactions.insertAll(<NormalizedTransaction>[
      NormalizedTransaction(
        source: BillSource.wechat,
        sourceTransactionId: 'TEST-BK-$seq',
        uniqueKey: TransactionFingerprint.compute(
          source: BillSource.wechat,
          externalId: 'TEST-BK-$seq',
          transactionTime: time,
          amountCents: amountCents,
          merchant: merchant,
          description: '',
          paymentMethod: '',
        ),
        transactionTime: time,
        transactionTimeRaw: '',
        transactionType: TransactionType.expense,
        transactionTypeRaw: '',
        amountCents: amountCents,
        merchant: merchant,
        description: '测试商品',
        categoryId: categoryId,
        paymentMethod: '零钱',
        rawData: '{"cells":["示例原始行"]}',
        createdAt: time,
        updatedAt: time,
      ),
    ]);
  }

  group('导出', () {
    test('exportJson 默认**不含** raw_data（隐私边界）', () async {
      await insertTx(time: DateTime(2026, 9, 1), amountCents: 10000);

      final json = await service.exportJson();
      final bundle = service.parseJson(json);

      expect(bundle.transactions.length, 1);
      expect(bundle.includeRawData, isFalse);
      expect(
        bundle.transactions.single.containsKey('raw_data'),
        isFalse,
        reason: '默认导出不得包含账单原始行',
      );
      // 商户名等字段仍然保留（这是账单本体，不是"原始行"）
      expect(bundle.transactions.single['merchant'], '示例商户');
    });

    test('显式勾选后才包含 raw_data', () async {
      await insertTx(time: DateTime(2026, 9, 1), amountCents: 10000);

      final json = await service.exportJson(includeRawData: true);
      final bundle = service.parseJson(json);

      expect(bundle.includeRawData, isTrue);
      expect(bundle.transactions.single.containsKey('raw_data'), isTrue);
    });

    test('导出包含分类 / 规则 / 预算 / 设置', () async {
      final json = await service.exportJson();
      final bundle = service.parseJson(json);

      expect(bundle.categories.length, greaterThan(40));
      expect(bundle.categoryRules.length, greaterThan(10));
      expect(bundle.budgets, isEmpty);
      expect(bundle.version, backupFormatVersion);
    });

    test('exportCsv 带表头，金额带符号，逗号字段被转义', () async {
      await insertTx(
        time: DateTime(2026, 9, 1, 8, 30),
        amountCents: 3852,
        merchant: '示例超市, 生鲜',
      );

      final csv = await service.exportCsv();
      final lines = const LineSplitter().convert(csv);

      expect(lines.first, contains('交易时间'));
      expect(lines.first, contains('金额(元)'));
      expect(lines.length, 2);
      expect(lines[1], contains('-38.52'));
      expect(lines[1], contains('2026-09-01 08:30:00'));
      // 含逗号的商户名必须被双引号包裹
      expect(lines[1], contains('"示例超市, 生鲜"'));
    });
  });

  group('解析与校验', () {
    test('拒绝非备份文件', () {
      expect(
        () => service.parseJson('{"foo":"bar"}'),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('拒绝非法 JSON', () {
      expect(
        () => service.parseJson('not json at all'),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('拒绝版本过新的备份', () {
      final json = jsonEncode(<String, Object?>{
        'format': 'finance_hub_backup',
        'version': backupFormatVersion + 1,
        'exported_at': DateTime(2026, 9, 1).toIso8601String(),
      });
      expect(
        () => service.parseJson(json),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('拒绝缺少导出时间的备份', () {
      final json = jsonEncode(<String, Object?>{
        'format': 'finance_hub_backup',
        'version': 1,
      });
      expect(
        () => service.parseJson(json),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('preview 报告备份内容与当前数据量', () async {
      await insertTx(time: DateTime(2026, 9, 1), amountCents: 10000);
      final json = await service.exportJson();
      await insertTx(time: DateTime(2026, 9, 2), amountCents: 20000);

      final preview = await service.preview(service.parseJson(json));
      expect(preview.transactionCount, 1);
      expect(preview.currentTransactionCount, 2);
      expect(preview.categoryCount, greaterThan(40));
    });
  });

  group('恢复', () {
    test('merge 模式：写入备份交易并跳过重复', () async {
      await insertTx(time: DateTime(2026, 9, 1), amountCents: 10000);
      final json = await service.exportJson();
      final bundle = service.parseJson(json);

      // 再插一笔新的，让当前库有 2 条
      await insertTx(time: DateTime(2026, 9, 2), amountCents: 20000);
      expect(await transactions.count(), 2);

      final result = await service.restore(bundle, mode: RestoreMode.merge);

      expect(result.insertedTransactions, 0, reason: '备份里的那笔已存在');
      expect(result.skippedTransactions, 1);
      expect(result.softDeletedTransactions, 0);
      expect(await transactions.count(), 2, reason: '合并不删除现有数据');
    });

    test('merge 模式：备份里的新交易被写入', () async {
      await insertTx(time: DateTime(2026, 9, 1), amountCents: 10000);
      final bundle = service.parseJson(await service.exportJson());

      // 清空当前库（软删），模拟「换机后从备份恢复」
      final all = await store.selectAll('transactions');
      for (final row in all) {
        await transactions.softDelete(row['id'] as int);
      }
      expect(await transactions.count(), 0);

      final result = await service.restore(bundle, mode: RestoreMode.merge);
      expect(result.insertedTransactions, 1);
      expect(await transactions.count(), 1);
    });

    test('overwrite 模式：软删现有交易后再写入', () async {
      await insertTx(time: DateTime(2026, 9, 1), amountCents: 10000);
      final bundle = service.parseJson(await service.exportJson());

      // 当前库再加一笔备份里没有的
      await insertTx(time: DateTime(2026, 9, 2), amountCents: 20000);

      final result = await service.restore(bundle, mode: RestoreMode.overwrite);

      expect(result.softDeletedTransactions, 2);
      expect(await transactions.count(), 1, reason: '只剩备份里的那一笔');
      expect(
        await transactions.count(includeDeleted: true),
        3,
        reason: '被覆盖的 2 笔是软删除，仍可恢复',
      );
    });

    test('分类 id 按名称重映射，不会错位', () async {
      // 构造一个「旧库」的备份：分类 id 用 9001（本机不存在）
      final bundle = BackupBundle(
        exportedAt: DateTime(2026, 9, 1),
        categories: <Map<String, Object?>>[
          <String, Object?>{
            'id': 9001,
            'parent_id': null,
            'level': 1,
            'name': '宠物',
            'kind': 'expense',
            'sort_order': 99,
            'is_system': 0,
            'is_active': 1,
          },
        ],
        categoryRules: const <Map<String, Object?>>[],
        merchantRules: const <Map<String, Object?>>[],
        budgets: const <Map<String, Object?>>[],
        settings: const <String, String>{},
        transactions: <Map<String, Object?>>[
          <String, Object?>{
            'source': 'wechat',
            'unique_key': 'src:wechat:TEST-REMAP-1',
            'source_transaction_id': 'TEST-REMAP-1',
            'transaction_time':
                DateTime(2026, 9, 1).millisecondsSinceEpoch,
            'transaction_time_raw': '',
            'transaction_type': 'expense',
            'transaction_type_raw': '',
            'platform_category': '',
            'amount_cents': 12345,
            'currency': 'CNY',
            'merchant': '示例宠物店',
            'description': '',
            'category_id': 9001,
            'subcategory_id': null,
            'category_source': 'keyword',
            'payment_method': '',
            'status': 'success',
            'note': '',
            'created_at': DateTime(2026, 9, 1).millisecondsSinceEpoch,
            'updated_at': DateTime(2026, 9, 1).millisecondsSinceEpoch,
          },
        ],
      );

      final result = await service.restore(bundle, mode: RestoreMode.merge);
      expect(result.insertedTransactions, 1);

      // 分类被补建，交易指向本机的新 id
      final created = (await categories.loadAll())
          .firstWhere((item) => item.name == '宠物');
      final restored = (await transactions.findByRange(
        fromMillis: DateTime(2026, 1).millisecondsSinceEpoch,
        toMillis: DateTime(2027, 1).millisecondsSinceEpoch,
      ))
          .single;
      expect(restored.categoryId, created.id);
      expect(restored.categoryId, isNot(9001));
      expect(restored.merchant, '示例宠物店');
    });

    test('同名分类不会重复创建', () async {
      final food = (await categories.topLevel()).firstWhere(
        (item) => item.name == '餐饮',
      );
      final before = (await categories.loadAll()).length;

      final bundle = BackupBundle(
        exportedAt: DateTime(2026, 9, 1),
        categories: <Map<String, Object?>>[
          <String, Object?>{
            'id': 8001,
            'parent_id': null,
            'level': 1,
            'name': '餐饮',
            'kind': 'expense',
            'sort_order': 0,
            'is_system': 1,
            'is_active': 1,
          },
        ],
        categoryRules: const <Map<String, Object?>>[],
        merchantRules: const <Map<String, Object?>>[],
        budgets: const <Map<String, Object?>>[],
        settings: const <String, String>{},
        transactions: <Map<String, Object?>>[
          <String, Object?>{
            'source': 'wechat',
            'unique_key': 'src:wechat:TEST-REMAP-2',
            'source_transaction_id': 'TEST-REMAP-2',
            'transaction_time':
                DateTime(2026, 9, 2).millisecondsSinceEpoch,
            'transaction_time_raw': '',
            'transaction_type': 'expense',
            'transaction_type_raw': '',
            'platform_category': '',
            'amount_cents': 5000,
            'currency': 'CNY',
            'merchant': '示例餐厅',
            'description': '',
            'category_id': 8001,
            'subcategory_id': null,
            'category_source': 'keyword',
            'payment_method': '',
            'status': 'success',
            'note': '',
            'created_at': DateTime(2026, 9, 2).millisecondsSinceEpoch,
            'updated_at': DateTime(2026, 9, 2).millisecondsSinceEpoch,
          },
        ],
      );

      await service.restore(bundle, mode: RestoreMode.merge);

      expect(
        (await categories.loadAll()).length,
        before,
        reason: '同名分类应复用而不是新建',
      );
      final restored = (await transactions.findByRange(
        fromMillis: DateTime(2026, 1).millisecondsSinceEpoch,
        toMillis: DateTime(2027, 1).millisecondsSinceEpoch,
      ))
          .single;
      expect(restored.categoryId, food.id);
    });
  });
}
