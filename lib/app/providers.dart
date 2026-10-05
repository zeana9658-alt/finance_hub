import 'package:finance_hub/core/utils/date_range.dart';
import 'package:finance_hub/data/database/app_database.dart';
import 'package:finance_hub/data/repositories/analytics_dao.dart';
import 'package:finance_hub/data/repositories/backup_store_impl.dart';
import 'package:finance_hub/data/repositories/budget_repository_impl.dart';
import 'package:finance_hub/data/repositories/category_repository_impl.dart';
import 'package:finance_hub/data/repositories/rule_repository_impl.dart';
import 'package:finance_hub/data/repositories/transaction_repository_impl.dart';
import 'package:finance_hub/domain/entities/budget.dart';
import 'package:finance_hub/domain/entities/category.dart';
import 'package:finance_hub/domain/entities/normalized_transaction.dart';
import 'package:finance_hub/domain/entities/statistics.dart';
import 'package:finance_hub/domain/repositories/budget_repository.dart';
import 'package:finance_hub/domain/repositories/category_repository.dart';
import 'package:finance_hub/domain/repositories/rule_repository.dart';
import 'package:finance_hub/domain/repositories/transaction_repository.dart';
import 'package:finance_hub/domain/services/backup_service.dart';
import 'package:finance_hub/domain/services/categorization_engine.dart';
import 'package:finance_hub/domain/services/engine_builder.dart';
import 'package:finance_hub/domain/services/import_pipeline.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 基础层：数据库单例。
///
/// 用 Riverpod 的 `Provider` 承载，测试时可用 `ProviderScope(overrides:)` 换成
/// 临时文件数据库，无需改动任何业务代码。
final appDatabaseProvider = Provider<AppDatabase>((Ref ref) {
  final database = AppDatabase();
  ref.onDispose(database.close);
  return database;
});

final transactionRepositoryProvider = Provider<TransactionRepository>(
  (Ref ref) => TransactionRepositoryImpl(ref.watch(appDatabaseProvider)),
);

final categoryRepositoryProvider = Provider<CategoryRepository>(
  (Ref ref) => CategoryRepositoryImpl(ref.watch(appDatabaseProvider)),
);

final ruleRepositoryProvider = Provider<RuleRepository>(
  (Ref ref) => RuleRepositoryImpl(ref.watch(appDatabaseProvider)),
);

final budgetRepositoryProvider = Provider<BudgetRepository>(
  (Ref ref) => BudgetRepositoryImpl(ref.watch(appDatabaseProvider)),
);

final analyticsDaoProvider = Provider<AnalyticsDao>(
  (Ref ref) => AnalyticsDao(ref.watch(appDatabaseProvider)),
);

final backupStoreProvider = Provider<BackupStore>(
  (Ref ref) => BackupStoreImpl(ref.watch(appDatabaseProvider)),
);

final backupServiceProvider = Provider<BackupService>(
  (Ref ref) => BackupService(ref.watch(backupStoreProvider)),
);

/// 当前选中的月份（首页与统计页共享）。
class SelectedMonthNotifier extends Notifier<DateTime> {
  @override
  DateTime build() => DateTime.now();

  void select(DateTime month) => state = DateTime(month.year, month.month);

  void previousMonth() => state = DateTime(state.year, state.month - 1);

  void nextMonth() => state = DateTime(state.year, state.month + 1);
}

final selectedMonthProvider =
    NotifierProvider<SelectedMonthNotifier, DateTime>(
  SelectedMonthNotifier.new,
);

/// 亮/暗模式。
class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.system;

  void select(ThemeMode mode) => state = mode;
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);

// ───────────────────── 分类 ─────────────────────

/// 全部启用的分类。
final allCategoriesProvider = FutureProvider<List<Category>>(
  (Ref ref) async => ref.watch(categoryRepositoryProvider).loadAll(),
);

/// `id → 名称` 映射。导入预览要用它把 `category_id` 渲染成中文名。
final categoryNameMapProvider = FutureProvider<Map<int, String>>(
  (Ref ref) async => ref.watch(categoryRepositoryProvider).nameMap(),
);

// ───────────────────── 分类引擎与导入流水线 ─────────────────────

/// 分类引擎 —— 从数据库加载**真实规则 + 商户记忆**，构建成纯函数引擎。
///
/// 关键点：引擎不再是无规则的空壳。修改规则后只要 invalidate 这个 provider，
/// 就能拿到新引擎重新分类（brief 第 11 条的「规则可重跑」）。
final categorizationEngineProvider =
    FutureProvider<CategorizationEngine>((Ref ref) async {
  // 构建逻辑抽在 buildCategorizationEngine 里，保证 provider 与测试
  // 走的是同一条路径（否则容易出现「测试过、线上不过」）。
  return buildCategorizationEngine(
    rules: await ref.watch(ruleRepositoryProvider).loadCategoryRules(),
    merchantRules: await ref.watch(ruleRepositoryProvider).loadMerchantRules(),
    categories: await ref.watch(categoryRepositoryProvider).loadAll(),
  );
});

/// 导入流水线（依赖分类引擎，因此是异步的）。
final importPipelineProvider = FutureProvider<ImportPipeline>((Ref ref) async {
  final engine = await ref.watch(categorizationEngineProvider.future);
  return ImportPipeline(categorizationEngine: engine);
});

// ───────────────────── 派生数据（自动缓存 + 失效） ─────────────────────

/// 本月汇总。
final monthSummaryProvider = FutureProvider<PeriodSummary>((Ref ref) async {
  final month = ref.watch(selectedMonthProvider);
  final dao = ref.watch(analyticsDaoProvider);
  final range = DateRanges.monthOf(month);
  return dao.summary(fromMillis: range.startMillis, toMillis: range.endMillis);
});

/// 上月汇总（用于环比）。
final previousMonthSummaryProvider =
    FutureProvider<PeriodSummary>((Ref ref) async {
  final month = ref.watch(selectedMonthProvider);
  final dao = ref.watch(analyticsDaoProvider);
  final range = DateRanges.previousMonth(month);
  return dao.summary(fromMillis: range.startMillis, toMillis: range.endMillis);
});

/// 本月分类占比。
final categoryTotalsProvider =
    FutureProvider<List<CategoryTotal>>((Ref ref) async {
  final month = ref.watch(selectedMonthProvider);
  final dao = ref.watch(analyticsDaoProvider);
  final range = DateRanges.monthOf(month);
  return dao.categoryTotals(
    fromMillis: range.startMillis,
    toMillis: range.endMillis,
  );
});

/// 本月大额支出 TOP 5。
final topExpensesProvider =
    FutureProvider<List<NormalizedTransaction>>((Ref ref) async {
  final month = ref.watch(selectedMonthProvider);
  final dao = ref.watch(analyticsDaoProvider);
  final range = DateRanges.monthOf(month);
  return dao.topExpenses(
    fromMillis: range.startMillis,
    toMillis: range.endMillis,
    limit: 5,
  );
});

/// 本月消费日历数据。
final dailyTotalsProvider =
    FutureProvider<List<DailyTotal>>((Ref ref) async {
  final month = ref.watch(selectedMonthProvider);
  final dao = ref.watch(analyticsDaoProvider);
  final range = DateRanges.monthOf(month);
  return dao.dailyTotals(
    fromMillis: range.startMillis,
    toMillis: range.endMillis,
  );
});

/// 本月消费时段分布。
final timeBucketTotalsProvider =
    FutureProvider<List<TimeBucketTotal>>((Ref ref) async {
  final month = ref.watch(selectedMonthProvider);
  final dao = ref.watch(analyticsDaoProvider);
  final range = DateRanges.monthOf(month);
  return dao.timeBucketTotals(
    fromMillis: range.startMillis,
    toMillis: range.endMillis,
  );
});

/// 最近 12 个月的收支趋势（缺失月自动补 0，保证时间轴连续）。
final monthlyTrendProvider = FutureProvider<List<MonthlyTotal>>((Ref ref) async {
  final month = ref.watch(selectedMonthProvider);
  final dao = ref.watch(analyticsDaoProvider);
  final endMonth = DateTime(month.year, month.month);
  final startMonth = DateTime(endMonth.year, endMonth.month - 11);
  final endRange = DateRanges.monthOf(endMonth);

  final sparse = await dao.monthlyTotals(
    fromMillis: startMonth.millisecondsSinceEpoch,
    toMillis: endRange.endMillis,
  );
  return MonthlyTotal.fillGaps(sparse, from: startMonth, to: endMonth);
});

/// 本月商户排行。
final merchantTotalsProvider = FutureProvider<List<MerchantStat>>(
  (Ref ref) async {
    final month = ref.watch(selectedMonthProvider);
    final dao = ref.watch(analyticsDaoProvider);
    final range = DateRanges.monthOf(month);
    return dao.merchantTotals(
      fromMillis: range.startMillis,
      toMillis: range.endMillis,
      limit: 30,
    );
  },
);

/// 预算执行情况（预算 + 本期已用）。
final budgetProgressProvider =
    FutureProvider<List<BudgetProgress>>((Ref ref) async {
  final repository = ref.watch(budgetRepositoryProvider);
  final dao = ref.watch(analyticsDaoProvider);
  final names = await ref.watch(categoryRepositoryProvider).nameMap();
  final budgets = await repository.loadActive();
  final now = DateTime.now();

  final result = <BudgetProgress>[];
  for (final budget in budgets) {
    final range = budget.period.rangeOf(now);
    final used = await dao.spentCents(
      categoryId: budget.subcategoryId == null ? budget.categoryId : null,
      subcategoryId: budget.subcategoryId,
      fromMillis: range.startMillis,
      toMillis: range.endMillis,
    );
    result.add(
      BudgetProgress(
        budget: budget,
        usedCents: used,
        categoryName: budget.categoryId == null
            ? '总预算'
            : (names[budget.categoryId] ?? '未知分类'),
        subcategoryName: budget.subcategoryId == null
            ? null
            : names[budget.subcategoryId],
        periodRange: range,
      ),
    );
  }
  return result;
});

/// 最近交易。
final recentTransactionsProvider =
    FutureProvider<List<NormalizedTransaction>>((Ref ref) async {
  final dao = ref.watch(analyticsDaoProvider);
  return dao.recent(limit: 10);
});

/// 交易总数（设置页与空态判断）。
final transactionCountProvider = FutureProvider<int>((Ref ref) async {
  final dao = ref.watch(analyticsDaoProvider);
  return dao.totalCount();
});

/// 数据时间跨度（最早一笔交易）。
final earliestTransactionProvider = FutureProvider<DateTime?>(
  (Ref ref) async => ref.watch(analyticsDaoProvider).earliestTime(),
);

/// 手动刷新所有派生数据的令牌。
///
/// 导入完成后调用 `ref.invalidate(allDataRefreshTokenProvider)` 即可让
/// 所有依赖它的 FutureProvider 重新查询。
final allDataRefreshTokenProvider = Provider<int>((Ref ref) => 0);
