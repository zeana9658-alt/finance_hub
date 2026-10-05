import 'dart:io';

import 'package:finance_hub/core/errors/app_error.dart';
import 'package:finance_hub/data/database/app_database.dart';
import 'package:finance_hub/data/repositories/category_repository_impl.dart';
import 'package:finance_hub/data/repositories/rule_repository_impl.dart';
import 'package:finance_hub/data/repositories/transaction_repository_impl.dart';
import 'package:finance_hub/domain/entities/category_rule.dart';
import 'package:finance_hub/domain/entities/normalized_transaction.dart';
import 'package:finance_hub/domain/enums/bill_source.dart';
import 'package:finance_hub/domain/enums/category_source.dart';
import 'package:finance_hub/domain/enums/transaction_status.dart';
import 'package:finance_hub/domain/enums/transaction_type.dart';
import 'package:finance_hub/domain/services/engine_builder.dart';
import 'package:finance_hub/domain/services/manual_entry.dart';
import 'package:finance_hub/domain/services/recategorization_service.dart';
import 'package:finance_hub/domain/services/transaction_fingerprint.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 快速记账（手动记一笔）的测试。
void main() {
  group('ManualEntry.build', () {
    final when = DateTime(2026, 10, 5, 14, 30);

    test('产出的交易字段正确', () {
      final tx = ManualEntry.build(
        type: TransactionType.expense,
        amountCents: 3852,
        occurredAt: when,
        categoryId: 1,
        subcategoryId: 2,
        merchant: ' 示例咖啡 ',
        note: ' 下午茶 ',
        paymentMethod: '微信零钱',
        externalId: 'TEST-MANUAL-1',
        now: when,
      );

      expect(tx.source, BillSource.manual);
      expect(tx.sourceTransactionId, 'TEST-MANUAL-1');
      expect(tx.transactionType, TransactionType.expense);
      expect(tx.amountCents, 3852);
      expect(tx.transactionTime, when);
      expect(tx.status, TransactionStatus.success);
      expect(tx.transactionTypeRaw, '手动记账');
      // 首尾空格被去掉
      expect(tx.merchant, '示例咖啡');
      expect(tx.note, '下午茶');
      expect(tx.paymentMethod, '微信零钱');
    });

    test('★ 分类来源固定为 manual —— 这样重跑不会覆盖它', () {
      final tx = ManualEntry.build(
        type: TransactionType.expense,
        amountCents: 100,
        occurredAt: when,
        categoryId: 5,
        externalId: 'TEST-MANUAL-2',
      );
      expect(tx.categorySource, CategorySource.manual);
      expect(tx.isCategoryLocked, isTrue);
    });

    test('指纹基于生成的单号，而不是内容', () {
      final tx = ManualEntry.build(
        type: TransactionType.expense,
        amountCents: 100,
        occurredAt: when,
        categoryId: 5,
        externalId: 'TEST-MANUAL-3',
      );
      expect(tx.uniqueKey, 'src:manual:TEST-MANUAL-3');
      expect(TransactionFingerprint.isSourceIdBased(tx.uniqueKey), isTrue);
    });

    test('★ 同一天两笔金额商户完全相同的手动记账，指纹必须不同', () {
      // 如果用手动记账的内容做指纹，这两笔会被误判成重复而丢一笔
      final a = ManualEntry.build(
        type: TransactionType.expense,
        amountCents: 2800,
        occurredAt: when,
        categoryId: 1,
        merchant: '示例咖啡',
      );
      final b = ManualEntry.build(
        type: TransactionType.expense,
        amountCents: 2800,
        occurredAt: when,
        categoryId: 1,
        merchant: '示例咖啡',
      );
      expect(a.uniqueKey, isNot(b.uniqueKey));
    });

    test('generateExternalId 不重复', () {
      final ids = <String>{};
      for (var i = 0; i < 500; i++) {
        ids.add(ManualEntry.generateExternalId());
      }
      expect(ids.length, 500);
    });

    test('金额为 0 或负数被拒绝', () {
      expect(
        () => ManualEntry.build(
          type: TransactionType.expense,
          amountCents: 0,
          occurredAt: when,
        ),
        throwsA(isA<AppException>()),
      );
      expect(
        () => ManualEntry.build(
          type: TransactionType.expense,
          amountCents: -100,
          occurredAt: when,
        ),
        throwsA(isA<AppException>()),
      );
    });

    test('转账 / 退款不被手动记账支持', () {
      for (final type in <TransactionType>[
        TransactionType.transfer,
        TransactionType.refund,
      ]) {
        expect(
          () => ManualEntry.build(
            type: type,
            amountCents: 100,
            occurredAt: when,
          ),
          throwsA(isA<AppException>()),
          reason: '$type 应该被拒绝',
        );
      }
    });
  });

  // ───────────────────────── 落库与重跑 ─────────────────────────

  group('手动记账落库后', () {
    late Directory tempDir;
    late AppDatabase database;
    late TransactionRepositoryImpl transactions;
    late CategoryRepositoryImpl categories;
    late RuleRepositoryImpl rules;

    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('finance_hub_manual_');
      database = AppDatabase(databasePath: p.join(tempDir.path, 'test.sqlite'));
      await database.open();
      transactions = TransactionRepositoryImpl(database);
      categories = CategoryRepositoryImpl(database);
      rules = RuleRepositoryImpl(database);
    });

    tearDown(() async {
      await database.close();
    });

    Future<int> insertManual({
      required String merchant,
      required int amountCents,
      required int categoryId,
      TransactionType type = TransactionType.expense,
    }) async {
      final tx = ManualEntry.build(
        type: type,
        amountCents: amountCents,
        occurredAt: DateTime(2026, 10, 5, 14, 30),
        categoryId: categoryId,
        merchant: merchant,
      );
      await transactions.insertAll(<NormalizedTransaction>[tx]);
      final rows = await transactions.findAll();
      return rows.firstWhere((row) => row.uniqueKey == tx.uniqueKey).id!;
    }

    test('两笔完全相同的手动记账都能写进去', () async {
      final food = (await categories.topLevel())
          .firstWhere((item) => item.name == '餐饮');

      await insertManual(
        merchant: '示例咖啡',
        amountCents: 2800,
        categoryId: food.id!,
      );
      await insertManual(
        merchant: '示例咖啡',
        amountCents: 2800,
        categoryId: food.id!,
      );

      expect(
        await transactions.count(),
        2,
        reason: '同额同商户的两笔手记不该被去重',
      );
    });

    test('★ 手动记账的分类能扛住「重新分类历史账单」', () async {
      // 先造一条规则，制造"规则想改它"的场景
      final food = (await categories.topLevel())
          .firstWhere((item) => item.name == '餐饮');
      await rules.createRule(
        CategoryRule(
          name: '测试规则',
          priority: 1,
          merchantContains: const <String>['示例咖啡'],
          targetCategoryId: food.id!,
        ),
      );

      // 用户手记时选的是「购物」（与规则不一致）
      final shopping = (await categories.topLevel())
          .firstWhere((item) => item.name == '购物');
      final id = await insertManual(
        merchant: '示例咖啡',
        amountCents: 2800,
        categoryId: shopping.id!,
      );

      // 跑一次重分类
      final engine = buildCategorizationEngine(
        rules: await rules.loadCategoryRules(),
        merchantRules: await rules.loadMerchantRules(),
        categories: await categories.loadAll(),
      );
      final result = await RecategorizationService(
        repository: transactions,
        engine: engine,
      ).run();

      expect(result.skippedManual, 1);
      expect(result.changed, 0);

      final after = (await transactions.findAll())
          .firstWhere((row) => row.id == id);
      expect(after.categoryId, shopping.id, reason: '手动记账的分类不能被重跑改写');
      expect(after.categorySource, CategorySource.manual);
    });

    test('手动记账在账单列表里能按来源区分', () async {
      final food = (await categories.topLevel())
          .firstWhere((item) => item.name == '餐饮');
      await insertManual(
        merchant: '示例咖啡',
        amountCents: 2800,
        categoryId: food.id!,
      );

      final rows = await transactions.findAll();
      expect(rows.single.source, BillSource.manual);
      expect(rows.single.source.label, '手动记账');
    });

    test('手动记的收入也能正常落库并计入统计口径', () async {
      final salary = (await categories.topLevel())
          .firstWhere((item) => item.name == '工资');
      await insertManual(
        merchant: '示例公司',
        amountCents: 500000,
        categoryId: salary.id!,
        type: TransactionType.income,
      );

      final rows = await transactions.findAll();
      expect(rows.single.transactionType, TransactionType.income);
      expect(rows.single.signedCents, 500000);
      expect(rows.single.countsInStatistics, isTrue);
    });
  });
}
