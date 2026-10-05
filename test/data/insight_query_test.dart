import 'dart:io';

import 'package:finance_hub/data/database/app_database.dart';
import 'package:finance_hub/data/repositories/analytics_dao.dart';
import 'package:finance_hub/data/repositories/category_repository_impl.dart';
import 'package:finance_hub/data/repositories/insight_query_engine.dart';
import 'package:finance_hub/data/repositories/transaction_repository_impl.dart';
import 'package:finance_hub/domain/entities/normalized_transaction.dart';
import 'package:finance_hub/domain/enums/bill_source.dart';
import 'package:finance_hub/domain/enums/transaction_type.dart';
import 'package:finance_hub/domain/services/intent_parser.dart';
import 'package:finance_hub/domain/services/transaction_fingerprint.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 自然语言查询的端到端集成测试：
/// 问法 → 本地意图解析 → 本地 SQL → 真实数据。
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tempDir;
  late AppDatabase database;
  late TransactionRepositoryImpl transactions;
  late CategoryRepositoryImpl categories;
  late AnalyticsDao analytics;
  late InsightQueryEngine engine;

  /// 固定"今天"，让相对时间断言可复现。
  final now = DateTime(2026, 10, 5, 14, 30);

  var seq = 0;

  Future<void> insertTx({
    required DateTime time,
    required int amountCents,
    required String merchant,
    int? categoryId,
    int? subcategoryId,
    TransactionType type = TransactionType.expense,
  }) async {
    seq++;
    final id = 'TEST-NLQ-$seq';
    await transactions.insertAll(<NormalizedTransaction>[
      NormalizedTransaction(
        source: BillSource.wechat,
        sourceTransactionId: id,
        uniqueKey: TransactionFingerprint.compute(
          source: BillSource.wechat,
          externalId: id,
          transactionTime: time,
          amountCents: amountCents,
          merchant: merchant,
          description: '',
          paymentMethod: '零钱',
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
      ),
    ]);
  }

  /// 种子数据（金额单位：分）
  ///
  /// | 时间 | 分类 | 商户 | 金额 |
  /// |---|---|---|---|
  /// | 2026-08-15 | 购物/电商 | 示例电商 | 10000 |
  /// | 2026-09-10 | 餐饮/咖啡茶饮 | 示例咖啡 | 3000 |
  /// | 2026-09-20 | 餐饮/快餐 | 示例快餐 | 2000 |
  /// | 2026-10-05 | 餐饮/咖啡茶饮 | 示例咖啡 | 5000 |
  /// | 2026-10-06 | 餐饮/快餐 | 示例快餐 | 4000 |
  /// | 2026-10-06 | 工资（收入） | 示例公司 | 500000 |
  Future<void> seedData() async {
    final shopping = (await categories.topLevel())
        .firstWhere((item) => item.name == '购物');
    final ecommerce = (await categories.childrenOf(shopping.id!))
        .firstWhere((item) => item.name == '电商');
    final food = (await categories.topLevel())
        .firstWhere((item) => item.name == '餐饮');
    final coffee = (await categories.childrenOf(food.id!))
        .firstWhere((item) => item.name == '咖啡茶饮');
    final fastFood = (await categories.childrenOf(food.id!))
        .firstWhere((item) => item.name == '快餐');

    await insertTx(
      time: DateTime(2026, 8, 15, 12),
      amountCents: 10000,
      merchant: '示例电商',
      categoryId: shopping.id,
      subcategoryId: ecommerce.id,
    );
    await insertTx(
      time: DateTime(2026, 9, 10, 9),
      amountCents: 3000,
      merchant: '示例咖啡',
      categoryId: food.id,
      subcategoryId: coffee.id,
    );
    await insertTx(
      time: DateTime(2026, 9, 20, 12),
      amountCents: 2000,
      merchant: '示例快餐',
      categoryId: food.id,
      subcategoryId: fastFood.id,
    );
    await insertTx(
      time: DateTime(2026, 10, 5, 8),
      amountCents: 5000,
      merchant: '示例咖啡',
      categoryId: food.id,
      subcategoryId: coffee.id,
    );
    await insertTx(
      time: DateTime(2026, 10, 6, 12),
      amountCents: 4000,
      merchant: '示例快餐',
      categoryId: food.id,
      subcategoryId: fastFood.id,
    );
    await insertTx(
      time: DateTime(2026, 10, 6, 18),
      amountCents: 500000,
      merchant: '示例公司',
      type: TransactionType.income,
    );
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('finance_hub_nlq_');
    database = AppDatabase(databasePath: p.join(tempDir.path, 'test.sqlite'));
    await database.open();
    transactions = TransactionRepositoryImpl(database);
    categories = CategoryRepositoryImpl(database);
    analytics = AnalyticsDao(database);
    engine = InsightQueryEngine(analytics);
    await seedData();
  });

  tearDown(() async {
    await database.close();
  });

  Future<String> ask(String question) async {
    final intent = IntentParser.parse(question, now: now);
    final outcome = await engine.execute(intent, now: now);
    return outcome.answer;
  }

  group('分类关键词查询', () {
    test('「2026年在餐饮上花了多少」→ 含全部子分类', () async {
      final answer = await ask('2026年在餐饮上花了多少钱');
      // 3000 + 2000 + 5000 + 4000 = 14000
      expect(answer, contains('140.00'));
    });

    test('「在咖啡上花了多少」→ 只算二级分类「咖啡茶饮」', () async {
      final answer = await ask('2026年在咖啡上花了多少钱');
      // 3000 + 5000 = 8000
      expect(answer, contains('80.00'));
    });

    test('关键词不是分类时退化为商户模糊匹配', () async {
      final answer = await ask('示例咖啡上花了多少钱');
      // 3000 + 5000 = 8000
      expect(answer, contains('80.00'));
    });
  });

  group('最大单笔', () {
    test('「9月最大的支出」', () async {
      final intent = IntentParser.parse('9月最大的支出是什么', now: now);
      final outcome = await engine.execute(intent, now: now);
      expect(outcome.amountCents, 3000);
      expect(outcome.answer, contains('30.00'));
      // 本地展示可以带商户名（外发才禁止）
      expect(outcome.detail, contains('示例咖啡'));
    });

    test('限定分类后取该分类下的最大值', () async {
      final intent = IntentParser.parse('2026年餐饮最大的支出是什么', now: now);
      final outcome = await engine.execute(intent, now: now);
      expect(outcome.amountCents, 5000);
    });
  });

  group('哪个月花最多', () {
    test('「2026年哪个月花钱最多」→ 8 月（10000）', () async {
      final intent = IntentParser.parse('2026年哪个月花钱最多', now: now);
      final outcome = await engine.execute(intent, now: now);
      expect(outcome.amountCents, 10000);
      expect(outcome.answer, contains('2026年8月'));
    });
  });

  group('环比', () {
    test('「10月比9月多花了多少」→ 9000 - 5000 = 4000', () async {
      final intent = IntentParser.parse('10月比9月多花了多少钱', now: now);
      final outcome = await engine.execute(intent, now: now);
      // 10 月：5000 + 4000 = 9000；9 月：3000 + 2000 = 5000
      expect(outcome.comparisonCents, 5000);
      expect(outcome.amountCents, 4000);
      expect(outcome.answer, contains('多'));
      expect(outcome.answer, contains('40.00'));
    });

    test('「这个月比上个月多花了多少」', () async {
      final intent = IntentParser.parse('这个月比上个月多花了多少钱', now: now);
      final outcome = await engine.execute(intent, now: now);
      expect(outcome.comparisonCents, 5000);
      expect(outcome.amountCents, 4000);
    });
  });

  group('收入与结余', () {
    test('「2026年收入多少」', () async {
      final answer = await ask('2026年收入多少');
      expect(answer, contains('5,000.00'));
    });

    test('「2026年结余多少」→ 500000 - 24000', () async {
      final intent = IntentParser.parse('2026年结余多少', now: now);
      final outcome = await engine.execute(intent, now: now);
      // 支出合计 10000+3000+2000+5000+4000 = 24000
      expect(outcome.amountCents, 500000 - 24000);
    });
  });

  group('笔数', () {
    test('「这个月多少笔交易」→ 10 月共 3 笔', () async {
      final answer = await ask('这个月多少笔交易');
      expect(answer, contains('3 笔'));
    });
  });

  group('区间边界', () {
    test('「去年」查不到数据时给出明确回答而不是报错', () async {
      final answer = await ask('去年在餐饮上花了多少钱');
      expect(answer, contains('2025年'));
      expect(answer, contains('没有支出记录'));
    });

    test('全部时间不限定时间范围', () async {
      final intent = IntentParser.parse('我花了多少钱', now: now);
      final outcome = await engine.execute(intent, now: now);
      // 全部支出 = 24000
      expect(outcome.amountCents, 24000);
    });
  });

  group('无法理解', () {
    test('给出示例提示而不是崩溃', () async {
      final answer = await ask('今天天气怎么样');
      expect(answer, contains('没听懂'));
      expect(answer, contains('我今年在餐饮上花了多少钱'));
    });
  });

  group('分类名解析', () {
    test('精确匹配优先', () async {
      final id = await analytics.findCategoryIdByName('餐饮');
      final food = (await categories.topLevel())
          .firstWhere((item) => item.name == '餐饮');
      expect(id, food.id);
    });

    test('模糊匹配二级分类', () async {
      final id = await analytics.findCategoryIdByName('咖啡');
      final coffee = (await categories.loadAll())
          .firstWhere((item) => item.name == '咖啡茶饮');
      expect(id, coffee.id);
    });

    test('匹配不到返回 null', () async {
      expect(await analytics.findCategoryIdByName('完全不存在的分类'), isNull);
    });

    test('categoryWithChildren 含自身与全部子分类', () async {
      final food = (await categories.topLevel())
          .firstWhere((item) => item.name == '餐饮');
      final ids = await analytics.categoryWithChildren(food.id!);
      expect(ids, contains(food.id));
      // 餐饮下有 6 个二级分类
      expect(ids.length, 7);
    });
  });
}
