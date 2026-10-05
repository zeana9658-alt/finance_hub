import 'package:finance_hub/domain/entities/category_rule.dart';
import 'package:finance_hub/domain/entities/merchant_rule.dart';
import 'package:finance_hub/domain/entities/normalized_transaction.dart';
import 'package:finance_hub/domain/enums/bill_source.dart';
import 'package:finance_hub/domain/enums/category_source.dart';
import 'package:finance_hub/domain/enums/transaction_type.dart';
import 'package:finance_hub/domain/services/categorization_engine.dart';
import 'package:finance_hub/domain/services/transaction_fingerprint.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  NormalizedTransaction tx({
    BillSource source = BillSource.wechat,
    String merchant = '示例咖啡',
    String description = '拿铁',
    int amountCents = 2800,
    String platformCategory = '',
    TransactionType type = TransactionType.expense,
  }) {
    final when = DateTime(2026, 6, 12, 8, 30);
    return NormalizedTransaction(
      source: source,
      uniqueKey: TransactionFingerprint.compute(
        source: source,
        externalId: 'TEST-${merchant.hashCode}',
        transactionTime: when,
        amountCents: amountCents,
        merchant: merchant,
        description: description,
        paymentMethod: '零钱',
      ),
      transactionTime: when,
      transactionTimeRaw: '',
      transactionType: type,
      transactionTypeRaw: '',
      platformCategory: platformCategory,
      amountCents: amountCents,
      merchant: merchant,
      description: description,
      paymentMethod: '零钱',
      createdAt: when,
      updatedAt: when,
    );
  }

  group('第一优先级：商户记忆', () {
    const engine = CategorizationEngine(
      merchantRules: <MerchantRule>[
        MerchantRule(
          merchantDisplay: '示例咖啡',
          categoryId: 1,
          subcategoryId: 4,
        ),
      ],
      rules: <CategoryRule>[
        CategoryRule(
          name: '会命中但优先级更低',
          priority: 1,
          merchantContains: <String>['示例咖啡'],
          targetCategoryId: 99,
        ),
      ],
    );

    test('商户记忆压过关键词规则', () {
      final assignment = engine.categorize(tx());
      expect(assignment.source, CategorySource.merchantMemory);
      expect(assignment.categoryId, 1);
      expect(assignment.subcategoryId, 4);
    });

    test('商户名归一化后仍能命中（空格/符号差异）', () {
      final assignment = engine.categorize(tx(merchant: '示例咖啡 '));
      expect(assignment.source, CategorySource.merchantMemory);
    });

    test('不同商户不命中', () {
      final assignment = engine.categorize(tx(merchant: '示例超市'));
      expect(assignment.source, isNot(CategorySource.merchantMemory));
    });
  });

  group('第二优先级：平台原始分类', () {
    const engine = CategorizationEngine(
      platformCategoryMap: <String, CategoryAssignment>{
        '餐饮美食': CategoryAssignment(
          source: CategorySource.platform,
          categoryId: 1,
          subcategoryId: 2,
        ),
      },
      rules: <CategoryRule>[
        CategoryRule(
          name: '低优先级',
          priority: 1,
          merchantContains: <String>['示例'],
          targetCategoryId: 99,
        ),
      ],
    );

    test('平台分类命中', () {
      final assignment = engine.categorize(tx(platformCategory: '餐饮美食'));
      expect(assignment.source, CategorySource.platform);
      expect(assignment.categoryId, 1);
    });

    test('平台分类为空格变体也能命中', () {
      final assignment = engine.categorize(tx(platformCategory: '餐饮 美食'));
      expect(assignment.source, CategorySource.platform);
    });

    test('平台分类为空则往下走', () {
      final assignment = engine.categorize(tx());
      expect(assignment.source, CategorySource.keyword);
    });
  });

  group('第三优先级：关键词规则', () {
    test('按 priority 升序取第一条命中', () {
      const engine = CategorizationEngine(
        rules: <CategoryRule>[
          CategoryRule(
            name: '低优先级宽规则',
            priority: 50,
            merchantContains: <String>['示例'],
            targetCategoryId: 100,
          ),
          CategoryRule(
            name: '高优先级窄规则',
            priority: 10,
            merchantContains: <String>['示例咖啡'],
            targetCategoryId: 200,
          ),
        ],
      );
      final assignment = engine.categorize(tx());
      expect(assignment.categoryId, 200);
    });

    test('matchMode.merchantAndDescription 需要两个条件同时命中', () {
      const engine = CategorizationEngine(
        rules: <CategoryRule>[
          CategoryRule(
            name: '外卖平台',
            priority: 20,
            merchantContains: <String>['示例平台'],
            descriptionContains: <String>['外卖'],
            matchMode: RuleMatchMode.merchantAndDescription,
            targetCategoryId: 7,
          ),
        ],
      );

      // 只命中商户
      expect(
        engine.categorize(tx(merchant: '示例平台', description: '打车')).isAssigned,
        isFalse,
      );
      // 只命中描述
      expect(
        engine.categorize(tx(merchant: '示例其他', description: '外卖')).isAssigned,
        isFalse,
      );
      // 两个都命中
      final hit = engine.categorize(tx(merchant: '示例平台', description: '外卖订单'));
      expect(hit.categoryId, 7);
      expect(hit.source, CategorySource.keyword);
    });

    test('matchMode.any 任一命中', () {
      const engine = CategorizationEngine(
        rules: <CategoryRule>[
          CategoryRule(
            name: '任一',
            priority: 20,
            merchantContains: <String>['示例咖啡'],
            descriptionContains: <String>['拿铁'],
            targetCategoryId: 3,
          ),
        ],
      );
      expect(engine.categorize(tx(description: '')).categoryId, 3);
    });

    test('matchMode.all 需要全部命中', () {
      const engine = CategorizationEngine(
        rules: <CategoryRule>[
          CategoryRule(
            name: '全部',
            priority: 20,
            merchantContains: <String>['示例咖啡'],
            descriptionContains: <String>['拿铁'],
            matchMode: RuleMatchMode.all,
            targetCategoryId: 4,
          ),
        ],
      );
      expect(engine.categorize(tx()).categoryId, 4);
      expect(engine.categorize(tx(description: '美式')).isAssigned, isFalse);
    });

    test('禁用规则不生效', () {
      const engine = CategorizationEngine(
        rules: <CategoryRule>[
          CategoryRule(
            name: '禁用',
            priority: 1,
            enabled: false,
            merchantContains: <String>['示例咖啡'],
            targetCategoryId: 5,
          ),
        ],
      );
      expect(engine.categorize(tx()).isAssigned, isFalse);
    });

    test('来源限定生效', () {
      const engine = CategorizationEngine(
        rules: <CategoryRule>[
          CategoryRule(
            name: '仅支付宝',
            priority: 1,
            source: BillSource.alipay,
            merchantContains: <String>['示例咖啡'],
            targetCategoryId: 6,
          ),
        ],
      );
      expect(engine.categorize(tx(source: BillSource.wechat)).isAssigned, isFalse);
      expect(
        engine.categorize(tx(source: BillSource.alipay)).categoryId,
        6,
      );
    });

    test('方向限定生效', () {
      const engine = CategorizationEngine(
        rules: <CategoryRule>[
          CategoryRule(
            name: '仅收入',
            priority: 1,
            direction: TransactionType.income,
            merchantContains: <String>['示例咖啡'],
            targetCategoryId: 8,
          ),
        ],
      );
      expect(engine.categorize(tx()).isAssigned, isFalse);
      expect(engine.categorize(tx(type: TransactionType.income)).categoryId, 8);
    });

    test('金额区间限定生效', () {
      const engine = CategorizationEngine(
        rules: <CategoryRule>[
          CategoryRule(
            name: '大额',
            priority: 1,
            merchantContains: <String>['示例咖啡'],
            amountMinCents: 10000,
            targetCategoryId: 9,
          ),
        ],
      );
      expect(engine.categorize(tx(amountCents: 2800)).isAssigned, isFalse);
      expect(engine.categorize(tx(amountCents: 20000)).categoryId, 9);
    });
  });

  group('兜底', () {
    test('无规则时返回未分类', () {
      const engine = CategorizationEngine();
      final assignment = engine.categorize(tx());
      expect(assignment.source, CategorySource.fallback);
      expect(assignment.isAssigned, isFalse);
    });

    test('categorizeAll 与逐条结果一致', () {
      const engine = CategorizationEngine(
        rules: <CategoryRule>[
          CategoryRule(
            name: '咖啡',
            priority: 1,
            merchantContains: <String>['示例咖啡'],
            targetCategoryId: 3,
          ),
        ],
      );
      final list = <NormalizedTransaction>[tx(), tx(merchant: '示例超市')];
      final all = engine.categorizeAll(list);
      expect(all.length, 2);
      expect(all[0].categoryId, 3);
      expect(all[1].isAssigned, isFalse);
    });
  });
}
