import 'package:finance_hub/domain/entities/financial_summary.dart';
import 'package:finance_hub/domain/services/insight_generator.dart';
import 'package:flutter_test/flutter_test.dart';

/// 本地消费洞察生成器的单元测试（纯函数，不碰数据库）。
void main() {
  FinancialSummary build({
    int income = 0,
    int expense = 0,
    int count = 1,
    List<CategorySummaryItem> categories = const <CategorySummaryItem>[],
    List<DailySummaryItem> daily = const <DailySummaryItem>[],
    List<TimeBucketSummaryItem> buckets = const <TimeBucketSummaryItem>[],
    List<BudgetSummaryItem> budgets = const <BudgetSummaryItem>[],
    double? momChange,
  }) {
    return FinancialSummary(
      periodLabel: '2026-10',
      incomeCents: income,
      expenseCents: expense,
      balanceCents: income - expense,
      transactionCount: count,
      categoryStatistics: categories,
      dailyStatistics: daily,
      timeBucketStatistics: buckets,
      budgetStatus: budgets,
      trend: TrendSummary(momExpenseChange: momChange),
    );
  }

  List<String> titlesOf(List<Insight> insights) =>
      insights.map((insight) => insight.title).toList(growable: false);

  group('空数据', () {
    test('没有交易时给引导而不是报错', () {
      final insights = InsightGenerator.generate(build(count: 0));
      expect(insights.length, 1);
      expect(insights.single.title, contains('没有记录'));
    });
  });

  group('最大支出项', () {
    test('指出占比最高的分类', () {
      final insights = InsightGenerator.generate(
        build(
          expense: 100000,
          categories: const <CategorySummaryItem>[
            CategorySummaryItem(
              name: '餐饮',
              amountCents: 40000,
              ratio: 0.4,
              transactionCount: 20,
            ),
            CategorySummaryItem(
              name: '交通',
              amountCents: 10000,
              ratio: 0.1,
              transactionCount: 5,
            ),
          ],
        ),
      );
      final top = insights.first;
      expect(top.title, contains('餐饮'));
      expect(top.body, contains('40%'));
    });
  });

  group('支出集中度', () {
    test('前 3 类合计超过 60% 时给出提示', () {
      final insights = InsightGenerator.generate(
        build(
          expense: 100000,
          categories: const <CategorySummaryItem>[
            CategorySummaryItem(
              name: '餐饮',
              amountCents: 30000,
              ratio: 0.3,
              transactionCount: 10,
            ),
            CategorySummaryItem(
              name: '购物',
              amountCents: 25000,
              ratio: 0.25,
              transactionCount: 5,
            ),
            CategorySummaryItem(
              name: '娱乐',
              amountCents: 15000,
              ratio: 0.15,
              transactionCount: 3,
            ),
          ],
        ),
      );
      final concentrated = insights
          .where((item) => item.title.contains('前 3 类'))
          .toList(growable: false);
      expect(concentrated, hasLength(1));
      expect(concentrated.single.severity, InsightSeverity.attention);
    });

    test('分布分散时不提示集中度', () {
      final insights = InsightGenerator.generate(
        build(
          expense: 100000,
          categories: const <CategorySummaryItem>[
            CategorySummaryItem(
              name: '餐饮',
              amountCents: 20000,
              ratio: 0.2,
              transactionCount: 10,
            ),
            CategorySummaryItem(
              name: '购物',
              amountCents: 20000,
              ratio: 0.2,
              transactionCount: 5,
            ),
            CategorySummaryItem(
              name: '娱乐',
              amountCents: 15000,
              ratio: 0.15,
              transactionCount: 3,
            ),
          ],
        ),
      );
      expect(titlesOf(insights).where((t) => t.contains('前 3 类')), isEmpty);
    });
  });

  group('环比', () {
    test('增加超过 10% 提示注意', () {
      final insights = InsightGenerator.generate(
        build(expense: 100000, momChange: 0.25),
      );
      final trend = insights.firstWhere((item) => item.title.contains('增加'));
      expect(trend.severity, InsightSeverity.attention);
      expect(trend.title, contains('25.0%'));
    });

    test('减少超过 10% 是正面信号', () {
      final insights = InsightGenerator.generate(
        build(expense: 100000, momChange: -0.3),
      );
      final trend = insights.firstWhere((item) => item.title.contains('减少'));
      expect(trend.severity, InsightSeverity.positive);
    });

    test('小幅波动算持平', () {
      final insights = InsightGenerator.generate(
        build(expense: 100000, momChange: 0.02),
      );
      expect(titlesOf(insights).where((t) => t.contains('持平')), hasLength(1));
    });

    test('无法计算环比时不出现趋势条目', () {
      final insights = InsightGenerator.generate(
        build(expense: 100000, momChange: null),
      );
      expect(
        titlesOf(insights).where(
          (t) => t.contains('增加') || t.contains('减少') || t.contains('持平'),
        ),
        isEmpty,
      );
    });
  });

  group('夜间消费', () {
    test('21 点后占比超过 25% 提示', () {
      final insights = InsightGenerator.generate(
        build(
          expense: 100000,
          buckets: const <TimeBucketSummaryItem>[
            TimeBucketSummaryItem(
              bucket: '21:00–24:00',
              amountCents: 30000,
              ratio: 0.3,
            ),
            TimeBucketSummaryItem(
              bucket: '12:00–15:00',
              amountCents: 70000,
              ratio: 0.7,
            ),
          ],
        ),
      );
      expect(titlesOf(insights).where((t) => t.contains('夜间')), hasLength(1));
    });

    test('凌晨时段也算夜间', () {
      final insights = InsightGenerator.generate(
        build(
          expense: 100000,
          buckets: const <TimeBucketSummaryItem>[
            TimeBucketSummaryItem(
              bucket: '00:00–06:00',
              amountCents: 30000,
              ratio: 0.3,
            ),
            TimeBucketSummaryItem(
              bucket: '12:00–15:00',
              amountCents: 70000,
              ratio: 0.7,
            ),
          ],
        ),
      );
      expect(titlesOf(insights).where((t) => t.contains('夜间')), hasLength(1));
    });

    test('白天消费为主时不提示', () {
      final insights = InsightGenerator.generate(
        build(
          expense: 100000,
          buckets: const <TimeBucketSummaryItem>[
            TimeBucketSummaryItem(
              bucket: '12:00–15:00',
              amountCents: 90000,
              ratio: 0.9,
            ),
            TimeBucketSummaryItem(
              bucket: '21:00–24:00',
              amountCents: 10000,
              ratio: 0.1,
            ),
          ],
        ),
      );
      expect(titlesOf(insights).where((t) => t.contains('夜间')), isEmpty);
    });
  });

  group('周末规律', () {
    test('周末日均显著高于工作日时提示', () {
      // 2026-10-03 / 04 是周六周日
      final insights = InsightGenerator.generate(
        build(
          expense: 300000,
          daily: const <DailySummaryItem>[
            DailySummaryItem(
              day: '2026-10-03',
              incomeCents: 0,
              expenseCents: 100000,
            ),
            DailySummaryItem(
              day: '2026-10-04',
              incomeCents: 0,
              expenseCents: 100000,
            ),
            DailySummaryItem(
              day: '2026-10-05',
              incomeCents: 0,
              expenseCents: 50000,
            ),
            DailySummaryItem(
              day: '2026-10-06',
              incomeCents: 0,
              expenseCents: 50000,
            ),
          ],
        ),
      );
      expect(titlesOf(insights).where((t) => t.contains('周末')), hasLength(1));
    });
  });

  group('预算', () {
    test('超预算提示为 attention（不是刺眼红）', () {
      final insights = InsightGenerator.generate(
        build(
          expense: 100000,
          budgets: const <BudgetSummaryItem>[
            BudgetSummaryItem(
              category: '餐饮',
              limitCents: 80000,
              usedCents: 95000,
            ),
          ],
        ),
      );
      final over = insights.firstWhere((item) => item.title.contains('超出'));
      expect(over.severity, InsightSeverity.attention);
      expect(over.body, contains('150'));
    });

    test('接近上限（≥80%）也提示', () {
      final insights = InsightGenerator.generate(
        build(
          expense: 100000,
          budgets: const <BudgetSummaryItem>[
            BudgetSummaryItem(
              category: '餐饮',
              limitCents: 80000,
              usedCents: 70000,
            ),
          ],
        ),
      );
      expect(titlesOf(insights).where((t) => t.contains('接近上限')), hasLength(1));
    });

    test('远未达上限时不提示', () {
      final insights = InsightGenerator.generate(
        build(
          expense: 100000,
          budgets: const <BudgetSummaryItem>[
            BudgetSummaryItem(
              category: '餐饮',
              limitCents: 80000,
              usedCents: 20000,
            ),
          ],
        ),
      );
      expect(
        titlesOf(insights).where(
          (t) => t.contains('超出') || t.contains('接近上限'),
        ),
        isEmpty,
      );
    });
  });

  group('兜底', () {
    test('没有任何特征时给一句中性结论', () {
      final insights = InsightGenerator.generate(build(expense: 100000));
      expect(insights, isNotEmpty);
      expect(titlesOf(insights).first, contains('均衡'));
    });
  });
}
