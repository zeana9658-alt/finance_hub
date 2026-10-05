import 'dart:io';

import 'package:finance_hub/data/database/app_database.dart';
import 'package:finance_hub/data/repositories/category_repository_impl.dart';
import 'package:finance_hub/data/repositories/rule_repository_impl.dart';
import 'package:finance_hub/data/repositories/transaction_repository_impl.dart';
import 'package:finance_hub/domain/entities/category.dart';
import 'package:finance_hub/domain/entities/category_rule.dart';
import 'package:finance_hub/domain/entities/normalized_transaction.dart';
import 'package:finance_hub/domain/enums/bill_source.dart';
import 'package:finance_hub/domain/enums/category_source.dart';
import 'package:finance_hub/domain/enums/transaction_type.dart';
import 'package:finance_hub/domain/services/engine_builder.dart';
import 'package:finance_hub/domain/services/recategorization_service.dart';
import 'package:finance_hub/domain/services/transaction_fingerprint.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 重新分类历史账单的集成测试 —— brief 第 11 条的核心保障。
///
/// 关于测试数据的说明：账单相关的夹具（`test/fixtures/`）全部使用虚构商户名
/// （`示例咖啡` 之类）。但**分类规则**的种子数据用的是真实连锁品牌名
/// （瑞幸、麦当劳…）—— 那是公开品牌名，用于关键词匹配测试，不是用户数据。
/// 因此这里分两组：
/// - 用**自定义规则**测「重跑逻辑」（商户名保持虚构）
/// - 单独一组测**内置种子规则**确实能命中（用真实品牌名作为匹配串）
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tempDir;
  late AppDatabase database;
  late TransactionRepositoryImpl transactions;
  late CategoryRepositoryImpl categories;
  late RuleRepositoryImpl rules;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('finance_hub_recat_');
    database = AppDatabase(databasePath: p.join(tempDir.path, 'test.sqlite'));
    await database.open();
    transactions = TransactionRepositoryImpl(database);
    categories = CategoryRepositoryImpl(database);
    rules = RuleRepositoryImpl(database);
  });

  tearDown(() async {
    await database.close();
  });

  /// 测试专用规则：`示例咖啡` → 餐饮/咖啡茶饮。
  ///
  /// 刻意**不依赖内置规则的具体关键词** —— 这样调整种子数据时
  /// 重跑逻辑的测试不会跟着碎。
  Future<void> seedTestRule() async {
    final food = (await categories.topLevel())
        .firstWhere((item) => item.name == '餐饮');
    final coffee = (await categories.childrenOf(food.id!))
        .firstWhere((item) => item.name == '咖啡茶饮');
    await rules.createRule(
      CategoryRule(
        name: '测试用-咖啡',
        priority: 10,
        merchantContains: const <String>['示例咖啡'],
        targetCategoryId: food.id!,
        targetSubcategoryId: coffee.id,
      ),
    );
  }

  var seq = 0;

  Future<int> insertTx({
    required String merchant,
    int amountCents = 2800,
    int? categoryId,
    int? subcategoryId,
    CategorySource source = CategorySource.fallback,
  }) async {
    seq++;
    final when = DateTime(2026, 9, 1, 8, 30);
    final externalId = 'TEST-RC-$seq';
    await transactions.insertAll(<NormalizedTransaction>[
      NormalizedTransaction(
        source: BillSource.wechat,
        sourceTransactionId: externalId,
        uniqueKey: TransactionFingerprint.compute(
          source: BillSource.wechat,
          externalId: externalId,
          transactionTime: when,
          amountCents: amountCents,
          merchant: merchant,
          description: '',
          paymentMethod: '零钱',
        ),
        transactionTime: when,
        transactionTimeRaw: '',
        transactionType: TransactionType.expense,
        transactionTypeRaw: '',
        amountCents: amountCents,
        merchant: merchant,
        description: '',
        categoryId: categoryId,
        subcategoryId: subcategoryId,
        categorySource: source,
        paymentMethod: '零钱',
        createdAt: when,
        updatedAt: when,
      ),
    ]);
    final rows = await transactions.findAll();
    return rows.firstWhere((row) => row.sourceTransactionId == externalId).id!;
  }

  /// 用与 provider **完全相同**的路径构建引擎。
  Future<RecategorizationService> buildService() async {
    final engine = buildCategorizationEngine(
      rules: await rules.loadCategoryRules(),
      merchantRules: await rules.loadMerchantRules(),
      categories: await categories.loadAll(),
    );
    return RecategorizationService(repository: transactions, engine: engine);
  }

  Future<NormalizedTransaction> findById(int id) async {
    final all = await transactions.findAll();
    return all.firstWhere((row) => row.id == id);
  }

  // ───────────────────────── 重跑逻辑 ─────────────────────────

  group('重新分类：关键词规则生效', () {
    test('未分类的账单会被规则归类', () async {
      await seedTestRule();
      final id = await insertTx(merchant: '示例咖啡');

      final result = await (await buildService()).run();

      expect(result.totalTransactions, 1);
      expect(result.changed, 1);

      final after = await findById(id);
      expect(after.categoryId, isNotNull);
      expect(after.categorySource, CategorySource.keyword);
    });

    test('落到正确的二级分类', () async {
      await seedTestRule();
      final id = await insertTx(merchant: '示例咖啡');

      await (await buildService()).run();

      final coffee = (await categories.loadAll())
          .firstWhere((item) => item.name == '咖啡茶饮');
      expect((await findById(id)).subcategoryId, coffee.id);
    });

    test('没有规则命中时保持未分类，并计入 stillUncategorized', () async {
      await seedTestRule();
      await insertTx(merchant: '完全不存在的商户xyz');

      final result = await (await buildService()).run();

      expect(result.changed, 0);
      expect(result.stillUncategorized, 1);
    });

    test('规则禁用后不再命中', () async {
      await seedTestRule();
      final loaded = (await rules.loadCategoryRules())
          .firstWhere((rule) => rule.name == '测试用-咖啡');
      await rules.setRuleEnabled(loaded.id!, false);

      final id = await insertTx(merchant: '示例咖啡');
      final result = await (await buildService()).run();

      expect(result.changed, 0);
      expect((await findById(id)).categoryId, isNull);
    });

    test('修改规则目标分类后重跑会改写', () async {
      await seedTestRule();
      final id = await insertTx(merchant: '示例咖啡');
      await (await buildService()).run();

      final coffee = (await categories.loadAll())
          .firstWhere((item) => item.name == '咖啡茶饮');
      expect((await findById(id)).subcategoryId, coffee.id);

      // 把规则改成「交通 / 打车」
      final transport = (await categories.topLevel())
          .firstWhere((item) => item.name == '交通');
      final taxi = (await categories.childrenOf(transport.id!))
          .firstWhere((item) => item.name == '打车');
      final loaded = (await rules.loadCategoryRules())
          .firstWhere((rule) => rule.name == '测试用-咖啡');
      await rules.updateRule(
        loaded.copyWith(
          targetCategoryId: transport.id!,
          targetSubcategoryId: taxi.id,
        ),
      );

      final second = await (await buildService()).run();
      expect(second.changed, 1);
      expect((await findById(id)).categoryId, transport.id);
      expect((await findById(id)).subcategoryId, taxi.id);
    });
  });

  group('重新分类：★ 绝不覆盖手动分类（brief 第 11 条）', () {
    test('category_source = manual 的账单被完整跳过', () async {
      await seedTestRule();
      final shopping = (await categories.topLevel())
          .firstWhere((item) => item.name == '购物');
      final id = await insertTx(
        merchant: '示例咖啡',
        categoryId: shopping.id,
        source: CategorySource.manual,
      );

      final result = await (await buildService()).run();

      expect(result.skippedManual, 1);
      expect(result.changed, 0);

      final after = await findById(id);
      expect(after.categoryId, shopping.id, reason: '手动分类不能被改写');
      expect(after.categorySource, CategorySource.manual);
    });

    test('混合场景：手动保留、自动改写、未命中各归各位', () async {
      await seedTestRule();
      final shopping = (await categories.topLevel())
          .firstWhere((item) => item.name == '购物');
      final manualId = await insertTx(
        merchant: '示例咖啡',
        categoryId: shopping.id,
        source: CategorySource.manual,
      );
      final autoId = await insertTx(merchant: '示例咖啡');
      await insertTx(merchant: '完全不存在的商户xyz');

      final result = await (await buildService()).run();

      expect(result.totalTransactions, 3);
      expect(result.skippedManual, 1);
      expect(result.changed, 1);
      expect(result.stillUncategorized, 1);

      expect((await findById(manualId)).categorySource, CategorySource.manual);
      expect((await findById(manualId)).categoryId, shopping.id);
      expect((await findById(autoId)).categorySource, CategorySource.keyword);
    });

    test('用 updateCategory(markAsManual: true) 锁定后，重跑不会动它', () async {
      await seedTestRule();
      final id = await insertTx(merchant: '示例咖啡');
      await (await buildService()).run();
      expect((await findById(id)).categorySource, CategorySource.keyword);

      final shopping = (await categories.topLevel())
          .firstWhere((item) => item.name == '购物');
      await transactions.updateCategory(
        id: id,
        categoryId: shopping.id,
        subcategoryId: null,
        markAsManual: true,
      );

      final result = await (await buildService()).run();
      expect(result.skippedManual, 1);
      expect((await findById(id)).categoryId, shopping.id);
    });
  });

  group('重新分类：商户记忆是第一优先级', () {
    test('记住商户后，重跑会归到记忆的分类', () async {
      final shopping = (await categories.topLevel())
          .firstWhere((item) => item.name == '购物');
      final daily = (await categories.childrenOf(shopping.id!))
          .firstWhere((item) => item.name == '日用品');

      final id = await insertTx(merchant: '示例便利店');
      await rules.rememberMerchant(
        merchant: '示例便利店',
        categoryId: shopping.id!,
        subcategoryId: daily.id,
      );

      await (await buildService()).run();

      final after = await findById(id);
      expect(after.categoryId, shopping.id);
      expect(after.subcategoryId, daily.id);
      expect(after.categorySource, CategorySource.merchantMemory);
    });

    test('商户记忆压过关键词规则', () async {
      await seedTestRule();
      final transport = (await categories.topLevel())
          .firstWhere((item) => item.name == '交通');

      final id = await insertTx(merchant: '示例咖啡');
      await rules.rememberMerchant(
        merchant: '示例咖啡',
        categoryId: transport.id!,
      );

      await (await buildService()).run();

      final after = await findById(id);
      expect(after.categoryId, transport.id);
      expect(after.categorySource, CategorySource.merchantMemory);
    });
  });

  group('重新分类：只写变化行', () {
    test('重复重跑第二次不会再改写（幂等）', () async {
      await seedTestRule();
      await insertTx(merchant: '示例咖啡');
      final service = await buildService();

      expect((await service.run()).changed, 1);
      expect(
        (await service.run()).changed,
        0,
        reason: '分类结果没变就不该产生 UPDATE',
      );
    });
  });

  // ───────────────────────── 内置种子规则 ─────────────────────────

  group('内置种子规则', () {
    test('种子规则已写入且带关键词', () async {
      final loaded = await rules.loadCategoryRules();
      expect(loaded.length, greaterThan(10));

      final coffee = loaded.firstWhere((rule) => rule.name == '咖啡茶饮');
      expect(coffee.isBuiltin, isTrue);
      expect(coffee.enabled, isTrue);
      expect(coffee.merchantContains, contains('瑞幸'));
      expect(coffee.targetCategoryId, greaterThan(0));
    });

    test('真实品牌名会被种子规则命中并落到餐饮/咖啡茶饮', () async {
      final id = await insertTx(merchant: '瑞幸咖啡');

      await (await buildService()).run();

      final after = await findById(id);
      final food = (await categories.topLevel())
          .firstWhere((item) => item.name == '餐饮');
      final coffee = (await categories.childrenOf(food.id!))
          .firstWhere((item) => item.name == '咖啡茶饮');

      expect(after.categoryId, food.id);
      expect(after.subcategoryId, coffee.id);
      expect(after.categorySource, CategorySource.keyword);
    });

    test('快餐连锁规则命中并落到餐饮/快餐', () async {
      final id = await insertTx(merchant: '麦当劳');

      await (await buildService()).run();

      final after = await findById(id);
      final food = (await categories.topLevel())
          .firstWhere((item) => item.name == '餐饮');
      final fastFood = (await categories.childrenOf(food.id!))
          .firstWhere((item) => item.name == '快餐');
      expect(after.subcategoryId, fastFood.id);
    });

    test('禁用内置规则后不再命中', () async {
      final builtin = (await rules.loadCategoryRules())
          .firstWhere((rule) => rule.name == '快餐连锁');
      await rules.setRuleEnabled(builtin.id!, false);

      final id = await insertTx(merchant: '麦当劳');
      final result = await (await buildService()).run();

      expect(result.changed, 0);
      expect((await findById(id)).categoryId, isNull);
    });
  });

  // ───────────────────────── 规则 CRUD ─────────────────────────

  group('规则 CRUD', () {
    test('新增自定义规则', () async {
      final pet = await categories.create(
        const Category(name: '宠物', level: 1, kind: CategoryKind.expense),
      );
      final id = await rules.createRule(
        CategoryRule(
          name: '宠物店',
          priority: 10,
          merchantContains: const <String>['示例宠物'],
          targetCategoryId: pet,
        ),
      );
      expect(id, greaterThan(0));

      final txId = await insertTx(merchant: '示例宠物店');
      await (await buildService()).run();
      expect((await findById(txId)).categoryId, pet);
    });

    test('删除自定义规则', () async {
      final ruleId = await rules.createRule(
        CategoryRule(
          name: '临时规则',
          priority: 1,
          merchantContains: const <String>['示例咖啡'],
          targetCategoryId: (await categories.topLevel()).first.id!,
        ),
      );
      await rules.deleteRule(ruleId);
      expect(
        (await rules.loadCategoryRules()).map((rule) => rule.id),
        isNot(contains(ruleId)),
      );
    });

    test('★ 内置规则删不掉（repository 层兜底）', () async {
      final builtin = (await rules.loadCategoryRules())
          .firstWhere((rule) => rule.isBuiltin);
      final before = (await rules.loadCategoryRules()).length;

      await rules.deleteRule(builtin.id!);

      expect(
        (await rules.loadCategoryRules()).length,
        before,
        reason: '内置规则只允许禁用，不允许删除',
      );
    });
  });

  // ───────────────────────── 商户记忆管理 ─────────────────────────

  group('商户记忆管理', () {
    test('clearMerchantRules 清空全部记忆', () async {
      final food = (await categories.topLevel())
          .firstWhere((item) => item.name == '餐饮');
      await rules.rememberMerchant(merchant: '示例A', categoryId: food.id!);
      await rules.rememberMerchant(merchant: '示例B', categoryId: food.id!);
      expect((await rules.loadMerchantRules()).length, 2);

      await rules.clearMerchantRules();
      expect(await rules.loadMerchantRules(), isEmpty);
    });
  });
}
