import 'dart:io';

import 'package:finance_hub/data/database/app_database.dart';
import 'package:finance_hub/data/repositories/analytics_dao.dart';
import 'package:finance_hub/data/repositories/budget_repository_impl.dart';
import 'package:finance_hub/data/repositories/category_repository_impl.dart';
import 'package:finance_hub/data/repositories/rule_repository_impl.dart';
import 'package:finance_hub/data/repositories/transaction_repository_impl.dart';
import 'package:finance_hub/domain/entities/budget.dart';
import 'package:finance_hub/domain/entities/category.dart';
import 'package:finance_hub/domain/entities/normalized_transaction.dart';
import 'package:finance_hub/domain/enums/bill_source.dart';
import 'package:finance_hub/domain/enums/transaction_type.dart';
import 'package:finance_hub/domain/services/transaction_fingerprint.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 统计 / 分类 / 预算 / 规则仓储的集成测试（真实 SQLite）。
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tempDir;
  late AppDatabase database;
  late TransactionRepositoryImpl transactions;
  late AnalyticsDao analytics;
  late CategoryRepositoryImpl categories;
  late BudgetRepositoryImpl budgets;
  late RuleRepositoryImpl rules;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('finance_hub_analytics_');
    database = AppDatabase(databasePath: p.join(tempDir.path, 'test.sqlite'));
    await database.open();
    transactions = TransactionRepositoryImpl(database);
    analytics = AnalyticsDao(database);
    categories = CategoryRepositoryImpl(database);
    budgets = BudgetRepositoryImpl(database);
    rules = RuleRepositoryImpl(database);
  });

  tearDown(() async {
    await database.close();
  });

  var seq = 0;

  /// 造一笔交易。
  Future<int> insertTx({
    required DateTime time,
    required int amountCents,
    TransactionType type = TransactionType.expense,
    String merchant = '示例商户',
    int? categoryId,
    int? subcategoryId,
    String source = 'wechat',
  }) async {
    seq++;
    final tx = NormalizedTransaction(
      source: BillSource.fromCode(source) ?? BillSource.wechat,
      sourceTransactionId: 'TEST-AN-$seq',
      uniqueKey: TransactionFingerprint.compute(
        source: BillSource.fromCode(source) ?? BillSource.wechat,
        externalId: 'TEST-AN-$seq',
        transactionTime: time,
        amountCents: amountCents,
        merchant: merchant,
        description: '',
        paymentMethod: '',
      ),
      transactionTime: time,
      transactionTimeRaw: '',
      transactionType: type,
      transactionTypeRaw: '',
      amountCents: amountCents,
      merchant: merchant,
      description: '',
      categoryId: categoryId,
      subcategoryId: subcategoryId,
      paymentMethod: '零钱',
      createdAt: time,
      updatedAt: time,
    );
    return transactions.insertAll(<NormalizedTransaction>[tx]);
  }

  int millis(DateTime time) => time.millisecondsSinceEpoch;

  // ───────────────────────── AnalyticsDao ─────────────────────────

  group('AnalyticsDao.monthlyTotals', () {
    test('按月分组，跨月正确', () async {
      await insertTx(time: DateTime(2026, 8, 5), amountCents: 10000);
      await insertTx(time: DateTime(2026, 8, 20), amountCents: 5000);
      await insertTx(time: DateTime(2026, 9, 3), amountCents: 20000);
      await insertTx(
        time: DateTime(2026, 9, 10),
        amountCents: 300000,
        type: TransactionType.income,
      );

      final rows = await analytics.monthlyTotals(
        fromMillis: millis(DateTime(2026, 1)),
        toMillis: millis(DateTime(2027, 1)),
      );
      expect(rows.length, 2);
      expect(rows[0].key, '2026-08');
      expect(rows[0].expenseCents, 15000);
      expect(rows[1].key, '2026-09');
      expect(rows[1].expenseCents, 20000);
      expect(rows[1].incomeCents, 300000);
    });

    test('退款计入 refundCents 并从净支出中冲减', () async {
      await insertTx(time: DateTime(2026, 9, 3), amountCents: 20000);
      await insertTx(
        time: DateTime(2026, 9, 5),
        amountCents: 5000,
        type: TransactionType.refund,
      );
      final rows = await analytics.monthlyTotals(
        fromMillis: millis(DateTime(2026, 9)),
        toMillis: millis(DateTime(2026, 10)),
      );
      expect(rows.single.expenseCents, 20000);
      expect(rows.single.refundCents, 5000);
      expect(rows.single.netExpenseCents, 15000);
    });

    test('区间外的交易不计入', () async {
      await insertTx(time: DateTime(2025, 12, 31), amountCents: 99999);
      final rows = await analytics.monthlyTotals(
        fromMillis: millis(DateTime(2026, 1)),
        toMillis: millis(DateTime(2027, 1)),
      );
      expect(rows, isEmpty);
    });
  });

  group('AnalyticsDao.merchantTotals', () {
    test('按商户排行，金额降序', () async {
      await insertTx(
        time: DateTime(2026, 9, 1),
        amountCents: 10000,
        merchant: '示例咖啡',
      );
      await insertTx(
        time: DateTime(2026, 9, 2),
        amountCents: 10000,
        merchant: '示例咖啡',
      );
      await insertTx(
        time: DateTime(2026, 9, 3),
        amountCents: 5000,
        merchant: '示例超市',
      );

      final rows = await analytics.merchantTotals(
        fromMillis: millis(DateTime(2026, 9)),
        toMillis: millis(DateTime(2026, 10)),
      );
      expect(rows.length, 2);
      expect(rows[0].merchant, '示例咖啡');
      expect(rows[0].totalCents, 20000);
      expect(rows[0].transactionCount, 2);
      expect(rows[0].averageCents, 10000);
      expect(rows[1].merchant, '示例超市');
    });

    test('可按分类筛选', () async {
      final food = (await categories.topLevel()).firstWhere(
        (item) => item.name == '餐饮',
      );
      final shopping = (await categories.topLevel()).firstWhere(
        (item) => item.name == '购物',
      );
      await insertTx(
        time: DateTime(2026, 9, 1),
        amountCents: 10000,
        merchant: '示例A',
        categoryId: food.id,
      );
      await insertTx(
        time: DateTime(2026, 9, 2),
        amountCents: 20000,
        merchant: '示例B',
        categoryId: shopping.id,
      );

      final rows = await analytics.merchantTotals(
        fromMillis: millis(DateTime(2026, 9)),
        toMillis: millis(DateTime(2026, 10)),
        categoryId: food.id,
      );
      expect(rows.length, 1);
      expect(rows.single.merchant, '示例A');
    });
  });

  group('AnalyticsDao.spentCents（预算执行）', () {
    test('按分类统计净支出，退款冲减', () async {
      final food = (await categories.topLevel()).firstWhere(
        (item) => item.name == '餐饮',
      );
      await insertTx(
        time: DateTime(2026, 9, 1),
        amountCents: 30000,
        categoryId: food.id,
      );
      await insertTx(
        time: DateTime(2026, 9, 2),
        amountCents: 8000,
        type: TransactionType.refund,
        categoryId: food.id,
      );

      final spent = await analytics.spentCents(
        categoryId: food.id,
        fromMillis: millis(DateTime(2026, 9)),
        toMillis: millis(DateTime(2026, 10)),
      );
      expect(spent, 22000);
    });

    test('不限分类时统计全部净支出', () async {
      await insertTx(time: DateTime(2026, 9, 1), amountCents: 12345);
      final spent = await analytics.spentCents(
        fromMillis: millis(DateTime(2026, 9)),
        toMillis: millis(DateTime(2026, 10)),
      );
      expect(spent, 12345);
    });
  });

  group('AnalyticsDao.categoryTotals 下钻', () {
    test('一级分类聚合 + 二级下钻', () async {
      final food = (await categories.topLevel()).firstWhere(
        (item) => item.name == '餐饮',
      );
      final children = await categories.childrenOf(food.id!);
      final fastFood = children.firstWhere((item) => item.name == '快餐');
      final coffee = children.firstWhere((item) => item.name == '咖啡茶饮');

      await insertTx(
        time: DateTime(2026, 9, 1),
        amountCents: 3000,
        categoryId: food.id,
        subcategoryId: fastFood.id,
      );
      await insertTx(
        time: DateTime(2026, 9, 2),
        amountCents: 2800,
        categoryId: food.id,
        subcategoryId: coffee.id,
      );

      final top = await analytics.categoryTotals(
        fromMillis: millis(DateTime(2026, 9)),
        toMillis: millis(DateTime(2026, 10)),
      );
      expect(top.length, 1);
      expect(top.single.name, '餐饮');
      expect(top.single.amountCents, 5800);

      final sub = await analytics.subcategoryTotals(
        parentCategoryId: food.id!,
        fromMillis: millis(DateTime(2026, 9)),
        toMillis: millis(DateTime(2026, 10)),
      );
      expect(sub.length, 2);
      expect(sub.first.name, '快餐');
      expect(sub.first.amountCents, 3000);
    });
  });

  // ───────────────────────── CategoryRepository ─────────────────────────

  group('CategoryRepository', () {
    test('种子分类：17 个一级 + 二级分类', () async {
      final all = await categories.loadAll();
      final top = all.where((item) => item.isTopLevel).toList();
      expect(top.length, 17);
      expect(top.map((item) => item.name), contains('餐饮'));
      expect(all.length, greaterThan(40));
    });

    test('nameMap 可用于渲染中文名', () async {
      final map = await categories.nameMap();
      expect(map.values, contains('餐饮'));
      expect(map.values, contains('咖啡茶饮'));
    });

    test('topLevel 可按收支过滤', () async {
      final income = await categories.topLevel(kind: CategoryKind.income);
      expect(income.map((item) => item.name), contains('工资'));
      expect(income.map((item) => item.name), isNot(contains('餐饮')));
    });

    test('childrenOf 返回二级分类', () async {
      final food = (await categories.topLevel()).firstWhere(
        (item) => item.name == '餐饮',
      );
      final children = await categories.childrenOf(food.id!);
      expect(children.length, 6);
      expect(children.first.name, '正餐');
    });

    test('create 与 topLevelNameExists', () async {
      expect(await categories.topLevelNameExists('宠物'), isFalse);
      final id = await categories.create(
        const Category(
          name: '宠物',
          level: 1,
          kind: CategoryKind.expense,
          icon: '🐾',
          sortOrder: 99,
        ),
      );
      expect(id, greaterThan(0));
      expect(await categories.topLevelNameExists('宠物'), isTrue);
      final all = await categories.loadAll();
      expect(all.map((item) => item.name), contains('宠物'));
    });

    test('deactivate 后不再出现在 loadAll 里', () async {
      final id = await categories.create(
        const Category(name: '临时分类', level: 1, kind: CategoryKind.expense),
      );
      await categories.deactivate(id);
      final all = await categories.loadAll();
      expect(all.map((item) => item.name), isNot(contains('临时分类')));
    });
  });

  // ───────────────────────── BudgetRepository ─────────────────────────

  group('BudgetRepository', () {
    test('upsert 新增与读取', () async {
      final food = (await categories.topLevel()).firstWhere(
        (item) => item.name == '餐饮',
      );
      await budgets.upsert(
        Budget(
          categoryId: food.id,
          amountCents: 80000,
          period: BudgetPeriod.monthly,
          startDate: DateTime(2026, 9),
        ),
      );
      final active = await budgets.loadActive();
      expect(active.length, 1);
      expect(active.single.amountCents, 80000);
      expect(active.single.period, BudgetPeriod.monthly);
    });

    test('同分类同周期重复设置 → 覆盖而不是报唯一约束错', () async {
      final food = (await categories.topLevel()).firstWhere(
        (item) => item.name == '餐饮',
      );
      await budgets.upsert(
        Budget(
          categoryId: food.id,
          amountCents: 50000,
          period: BudgetPeriod.monthly,
          startDate: DateTime(2026, 9),
        ),
      );
      await budgets.upsert(
        Budget(
          categoryId: food.id,
          amountCents: 90000,
          period: BudgetPeriod.monthly,
          startDate: DateTime(2026, 9),
        ),
      );
      final active = await budgets.loadActive();
      expect(active.length, 1, reason: '同分类同周期应只有一条启用预算');
      expect(active.single.amountCents, 90000);
    });

    test('不同周期可以并存', () async {
      final food = (await categories.topLevel()).firstWhere(
        (item) => item.name == '餐饮',
      );
      await budgets.upsert(
        Budget(
          categoryId: food.id,
          amountCents: 50000,
          period: BudgetPeriod.monthly,
          startDate: DateTime(2026, 9),
        ),
      );
      await budgets.upsert(
        Budget(
          categoryId: food.id,
          amountCents: 500000,
          period: BudgetPeriod.yearly,
          startDate: DateTime(2026, 1),
        ),
      );
      expect((await budgets.loadActive()).length, 2);
    });

    test('remove 删除预算', () async {
      final id = await budgets.upsert(
        Budget(
          amountCents: 100000,
          period: BudgetPeriod.monthly,
          startDate: DateTime(2026, 9),
        ),
      );
      expect((await budgets.loadActive()).length, 1);
      await budgets.remove(id);
      expect(await budgets.loadActive(), isEmpty);
    });

    test('setActive 停用后不再出现在 loadActive', () async {
      final id = await budgets.upsert(
        Budget(
          amountCents: 100000,
          period: BudgetPeriod.monthly,
          startDate: DateTime(2026, 9),
        ),
      );
      await budgets.setActive(id, false);
      expect(await budgets.loadActive(), isEmpty);
    });
  });

  // ───────────────────────── RuleRepository ─────────────────────────

  group('RuleRepository', () {
    test('种子规则的关键词 JSON 能被正确解析', () async {
      final loaded = await rules.loadCategoryRules();
      expect(loaded.length, greaterThan(10));

      final fastFood = loaded.firstWhere((rule) => rule.name == '快餐连锁');
      expect(fastFood.merchantContains, contains('麦当劳'));
      expect(fastFood.targetCategoryId, greaterThan(0));
      expect(fastFood.isBuiltin, isTrue);
      expect(fastFood.enabled, isTrue);
    });

    test('matchMode 为 merchant_and_description 的规则被正确读出', () async {
      final loaded = await rules.loadCategoryRules();
      final delivery = loaded.firstWhere((rule) => rule.name == '外卖平台');
      expect(delivery.descriptionContains, contains('外卖'));
      expect(delivery.matchMode.name, 'merchantAndDescription');
    });

    test('rememberMerchant 写入后可读回，且幂等', () async {
      final food = (await categories.topLevel()).firstWhere(
        (item) => item.name == '餐饮',
      );
      await rules.rememberMerchant(
        merchant: '示例咖啡',
        categoryId: food.id!,
      );
      await rules.rememberMerchant(
        merchant: '示例咖啡',
        categoryId: food.id!,
      );
      final memories = await rules.loadMerchantRules();
      expect(memories.length, 1, reason: '同商户同来源应只有一条记忆');
      expect(memories.single.merchantDisplay, '示例咖啡');
      expect(memories.single.categoryId, food.id);
    });

    test('forgetMerchant 删除记忆', () async {
      final food = (await categories.topLevel()).firstWhere(
        (item) => item.name == '餐饮',
      );
      await rules.rememberMerchant(merchant: '示例超市', categoryId: food.id!);
      expect((await rules.loadMerchantRules()).length, 1);
      await rules.forgetMerchant('示例超市');
      expect(await rules.loadMerchantRules(), isEmpty);
    });

    test('bumpRuleHits 累加命中次数', () async {
      final loaded = await rules.loadCategoryRules();
      final id = loaded.first.id!;
      await rules.bumpRuleHits(<int>[id]);
      await rules.bumpRuleHits(<int>[id]);
      final after = (await rules.loadCategoryRules())
          .firstWhere((rule) => rule.id == id);
      expect(after.hitCount, greaterThanOrEqualTo(2));
    });
  });
}
