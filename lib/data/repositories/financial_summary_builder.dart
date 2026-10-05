import 'package:finance_hub/core/utils/date_range.dart';
import 'package:finance_hub/data/repositories/analytics_dao.dart';
import 'package:finance_hub/domain/entities/financial_summary.dart';
import 'package:finance_hub/domain/entities/statistics.dart';
import 'package:finance_hub/domain/repositories/budget_repository.dart';
import 'package:finance_hub/domain/repositories/category_repository.dart';

/// 从本地数据库装配 [FinancialSummary]。
///
/// **这是隐私边界的守门人**：只从数据库里取**聚合结果**，
/// 从来不查单笔交易的商户名、订单号、备注。
/// 即使调用方想拼一个带商户名的 payload，这个构建器也不会提供那些字段。
class FinancialSummaryBuilder {
  const FinancialSummaryBuilder({
    required this.analytics,
    required this.categoryRepository,
    required this.budgetRepository,
  });

  final AnalyticsDao analytics;
  final CategoryRepository categoryRepository;
  final BudgetRepository budgetRepository;

  /// 构建某个月的摘要。
  Future<FinancialSummary> buildForMonth(DateTime month) async {
    final range = DateRanges.monthOf(month);
    final previous = DateRanges.previousMonth(month);

    final summary = await analytics.summary(
      fromMillis: range.startMillis,
      toMillis: range.endMillis,
    );
    final previousSummary = await analytics.summary(
      fromMillis: previous.startMillis,
      toMillis: previous.endMillis,
    );

    final categories = await analytics.categoryTotals(
      fromMillis: range.startMillis,
      toMillis: range.endMillis,
    );
    final daily = await analytics.dailyTotals(
      fromMillis: range.startMillis,
      toMillis: range.endMillis,
    );
    final buckets = await analytics.timeBucketTotals(
      fromMillis: range.startMillis,
      toMillis: range.endMillis,
    );

    final totalExpense = summary.netExpenseCents;

    return FinancialSummary(
      periodLabel: monthKey(month.year, month.month),
      incomeCents: summary.incomeCents,
      expenseCents: summary.expenseCents,
      balanceCents: summary.balanceCents,
      transactionCount: summary.transactionCount,
      categoryStatistics: categories
          .map(
            (item) => CategorySummaryItem(
              name: item.name,
              amountCents: item.amountCents,
              ratio: totalExpense == 0 ? 0 : item.amountCents / totalExpense,
              transactionCount: item.transactionCount,
            ),
          )
          .toList(growable: false),
      dailyStatistics: daily
          .map(
            (item) => DailySummaryItem(
              day: dayKey(item.day),
              incomeCents: item.incomeCents,
              expenseCents: item.expenseCents,
            ),
          )
          .toList(growable: false),
      timeBucketStatistics: _bucketItems(buckets, totalExpense),
      budgetStatus: await _budgetItems(month),
      trend: TrendSummary(
        momExpenseChange: summary.expenseChangeRate(previousSummary),
      ),
    );
  }

  List<TimeBucketSummaryItem> _bucketItems(
    List<TimeBucketTotal> buckets,
    int totalExpense,
  ) {
    final items = <TimeBucketSummaryItem>[];
    for (final bucket in buckets) {
      if (bucket.amountCents == 0) {
        continue;
      }
      items.add(
        TimeBucketSummaryItem(
          bucket: bucket.label,
          amountCents: bucket.amountCents,
          ratio: totalExpense == 0 ? 0 : bucket.amountCents / totalExpense,
        ),
      );
    }
    return items;
  }

  Future<List<BudgetSummaryItem>> _budgetItems(DateTime month) async {
    final budgets = await budgetRepository.loadActive();
    if (budgets.isEmpty) {
      return const <BudgetSummaryItem>[];
    }
    final names = await categoryRepository.nameMap();
    final items = <BudgetSummaryItem>[];

    for (final budget in budgets) {
      final range = budget.period.rangeOf(month);
      final used = await analytics.spentCents(
        categoryId: budget.subcategoryId == null ? budget.categoryId : null,
        subcategoryId: budget.subcategoryId,
        fromMillis: range.startMillis,
        toMillis: range.endMillis,
      );
      items.add(
        BudgetSummaryItem(
          category: budget.categoryId == null
              ? '总预算'
              : (names[budget.categoryId] ?? '未知分类'),
          limitCents: budget.amountCents,
          usedCents: used,
        ),
      );
    }
    return items;
  }
}
