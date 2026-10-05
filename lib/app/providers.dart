import 'package:finance_hub/core/utils/date_range.dart';
import 'package:finance_hub/data/database/app_database.dart';
import 'package:finance_hub/data/repositories/analytics_dao.dart';
import 'package:finance_hub/data/repositories/transaction_repository_impl.dart';
import 'package:finance_hub/domain/entities/normalized_transaction.dart';
import 'package:finance_hub/domain/entities/statistics.dart';
import 'package:finance_hub/domain/repositories/transaction_repository.dart';
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

final analyticsDaoProvider = Provider<AnalyticsDao>(
  (Ref ref) => AnalyticsDao(ref.watch(appDatabaseProvider)),
);

/// 导入流水线（纯函数服务，无状态）。
final importPipelineProvider =
    Provider<ImportPipeline>((Ref ref) => const ImportPipeline());

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

/// 手动刷新所有派生数据的令牌。
///
/// 导入完成后调用 `ref.invalidate(allDataRefreshTokenProvider)` 即可让
/// 所有依赖它的 FutureProvider 重新查询。
final allDataRefreshTokenProvider = Provider<int>((Ref ref) => 0);
