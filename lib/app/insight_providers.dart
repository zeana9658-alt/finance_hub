import 'package:finance_hub/app/providers.dart';
import 'package:finance_hub/data/repositories/financial_summary_builder.dart';
import 'package:finance_hub/data/repositories/insight_query_engine.dart';
import 'package:finance_hub/domain/entities/financial_summary.dart';
import 'package:finance_hub/domain/services/insight_generator.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 自然语言查询的本地执行器。
final insightQueryEngineProvider = Provider<InsightQueryEngine>(
  (Ref ref) => InsightQueryEngine(ref.watch(analyticsDaoProvider)),
);

/// 隐私边界载体 [FinancialSummary] 的构建器。
final financialSummaryBuilderProvider = Provider<FinancialSummaryBuilder>(
  (Ref ref) => FinancialSummaryBuilder(
    analytics: ref.watch(analyticsDaoProvider),
    categoryRepository: ref.watch(categoryRepositoryProvider),
    budgetRepository: ref.watch(budgetRepositoryProvider),
  ),
);

/// 当前选中月份的聚合摘要（**唯一允许外发的数据结构**）。
final financialSummaryProvider = FutureProvider<FinancialSummary>(
  (Ref ref) async {
    final month = ref.watch(selectedMonthProvider);
    return ref.watch(financialSummaryBuilderProvider).buildForMonth(month);
  },
);

/// 本地消费洞察（完全离线，不依赖任何模型）。
final insightsProvider = FutureProvider<List<Insight>>((Ref ref) async {
  final summary = await ref.watch(financialSummaryProvider.future);
  return InsightGenerator.generate(summary);
});
