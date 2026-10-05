import 'package:finance_hub/app/providers.dart';
import 'package:finance_hub/app/theme/app_colors.dart';
import 'package:finance_hub/core/money/money.dart';
import 'package:finance_hub/core/utils/date_range.dart';
import 'package:finance_hub/domain/entities/normalized_transaction.dart';
import 'package:finance_hub/domain/entities/statistics.dart';
import 'package:finance_hub/domain/enums/transaction_type.dart';
import 'package:finance_hub/features/import/import_entry.dart';
import 'package:finance_hub/shared/widgets/amount_text.dart';
import 'package:finance_hub/shared/widgets/app_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 首页 Dashboard —— 整个 App 最重要的页面。
///
/// 目标不是「传统财务软件」，而是让用户一眼看懂「我的钱去哪了」。
/// 布局顺序（docs/ARCHITECTURE.md §7.3：单屏卡片数 ≤ 4）：
/// 1. 月份切换 + 本月支出（含环比）
/// 2. 收入 / 支出 / 结余 三栏
/// 3. 分类占比（可下钻）
/// 4. 大额支出 TOP 5
/// 5. 最近交易
class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(selectedMonthProvider);
    final summary = ref.watch(monthSummaryProvider);
    final previous = ref.watch(previousMonthSummaryProvider);
    final categories = ref.watch(categoryTotalsProvider);
    final topExpenses = ref.watch(topExpensesProvider);
    final recent = ref.watch(recentTransactionsProvider);
    final count = ref.watch(transactionCountProvider);

    return Scaffold(
      appBar: AppBar(
        title: _MonthSwitcher(
          month: month,
          onPrevious: () => ref
              .read(selectedMonthProvider.notifier)
              .previousMonth(),
          onNext: () => ref.read(selectedMonthProvider.notifier).nextMonth(),
        ),
        actions: <Widget>[
          IconButton(
            tooltip: '导入账单',
            onPressed: () => ImportEntry.open(context, ref),
            icon: const Icon(Icons.file_download_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => ImportEntry.open(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('导入账单'),
      ),
      body: count.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stack) =>
            _ErrorView(message: '$error'),
        data: (int total) {
          if (total == 0) {
            return EmptyState(
              title: '还没有任何账单',
              description: '导入微信支付或支付宝导出的 CSV / XLSX 账单文件，'
                  'App 会在本地解析、去重、分类后展示统计。\n'
                  '全程离线，账单不会离开你的设备。',
              action: FilledButton.icon(
                onPressed: () => ImportEntry.open(context, ref),
                icon: const Icon(Icons.file_download_outlined),
                label: const Text('导入账单'),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              AppDimens.pagePadding,
              0,
              AppDimens.pagePadding,
              96,
            ),
            children: <Widget>[
              _HeroSummary(
                summary: summary.valueOrNull ?? PeriodSummary.empty,
                previous: previous.valueOrNull ?? PeriodSummary.empty,
                loading: summary.isLoading,
              ),
              const SizedBox(height: AppDimens.gapL),
              _CategoryBreakdown(categories: categories.valueOrNull ?? const <CategoryTotal>[]),
              const SizedBox(height: AppDimens.gapL),
              _TopExpenses(items: topExpenses.valueOrNull ?? const <NormalizedTransaction>[]),
              const SizedBox(height: AppDimens.gapL),
              _RecentTransactions(items: recent.valueOrNull ?? const <NormalizedTransaction>[]),
            ],
          );
        },
      ),
    );
  }
}

class _MonthSwitcher extends StatelessWidget {
  const _MonthSwitcher({
    required this.month,
    required this.onPrevious,
    required this.onNext,
  });

  final DateTime month;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        IconButton(
          onPressed: onPrevious,
          icon: const Icon(Icons.chevron_left),
          tooltip: '上个月',
          visualDensity: VisualDensity.compact,
        ),
        Text('${month.year}年${month.month}月'),
        IconButton(
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right),
          tooltip: '下个月',
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }
}

class _HeroSummary extends StatelessWidget {
  const _HeroSummary({
    required this.summary,
    required this.previous,
    required this.loading,
  });

  final PeriodSummary summary;
  final PeriodSummary previous;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rate = summary.expenseChangeRate(previous);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('本月支出', style: theme.textTheme.bodySmall),
          const SizedBox(height: AppDimens.gapS),
          Text(
            formatCents(summary.netExpenseCents, withSymbol: true),
            style: theme.textTheme.displaySmall,
          ),
          const SizedBox(height: AppDimens.gapS),
          if (loading)
            Text('计算中…', style: theme.textTheme.bodySmall)
          else if (rate == null)
            Text('上月无支出记录，无法计算环比', style: theme.textTheme.bodySmall)
          else
            _ChangeChip(rate: rate),
          const SizedBox(height: AppDimens.gapL),
          const Divider(height: 1),
          const SizedBox(height: AppDimens.gapL),
          Row(
            children: <Widget>[
              Expanded(
                child: _MiniStat(
                  label: '收入',
                  cents: summary.incomeCents,
                  type: TransactionType.income,
                ),
              ),
              Expanded(
                child: _MiniStat(
                  label: '支出',
                  cents: summary.expenseCents,
                  type: TransactionType.expense,
                ),
              ),
              Expanded(
                child: _MiniStat(
                  label: '结余',
                  cents: summary.balanceCents,
                  type: summary.balanceCents >= 0
                      ? TransactionType.income
                      : TransactionType.expense,
                ),
              ),
            ],
          ),
          if (summary.refundCents > 0) ...<Widget>[
            const SizedBox(height: AppDimens.gapM),
            Text(
              '其中退款 ${formatCents(summary.refundCents, withSymbol: true)}（已从支出中冲减）',
              style: theme.textTheme.labelSmall,
            ),
          ],
        ],
      ),
    );
  }
}

class _ChangeChip extends StatelessWidget {
  const _ChangeChip({required this.rate});

  final double rate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final up = rate > 0;
    final percent = (rate.abs() * 100).toStringAsFixed(1);

    // 支出增加用暖色、减少用绿色，但都是低饱和 —— 不做刺眼红绿警报
    final color = up
        ? (isDark ? const Color(0xFFD99B7E) : const Color(0xFFC67B5C))
        : (isDark ? const Color(0xFF8FBFA0) : const Color(0xFF5B8C6E));

    return Row(
      children: <Widget>[
        Icon(
          up ? Icons.trending_up : Icons.trending_down,
          size: 16,
          color: color,
        ),
        const SizedBox(width: 4),
        Text(
          '$percent%',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          up ? '比上月增加' : '比上月减少',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.cents,
    required this.type,
  });

  final String label;
  final int cents;
  final TransactionType type;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: theme.textTheme.labelSmall),
        const SizedBox(height: AppDimens.gapXs),
        AmountText(cents: cents, type: type, fontSize: 16),
      ],
    );
  }
}

class _CategoryBreakdown extends StatelessWidget {
  const _CategoryBreakdown({required this.categories});

  final List<CategoryTotal> categories;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (categories.isEmpty) {
      return AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('消费分类占比', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppDimens.gapM),
            Text('本月暂无支出记录', style: theme.textTheme.bodySmall),
          ],
        ),
      );
    }

    final total = categories.fold<int>(
      0,
      (sum, item) => sum + item.amountCents,
    );
    final isDark = theme.brightness == Brightness.dark;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('消费分类占比', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppDimens.gapL),
          for (var i = 0; i < categories.length && i < 8; i++) ...<Widget>[
            _CategoryRow(
              item: categories[i],
              totalCents: total,
              color: AppColors.parseHex(
                categories[i].color,
                fallback: AppColors.chartColor(i, isDark: isDark),
              ),
            ),
            if (i < categories.length - 1 && i < 7)
              const SizedBox(height: AppDimens.gapM),
          ],
        ],
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.item,
    required this.totalCents,
    required this.color,
  });

  final CategoryTotal item;
  final int totalCents;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ratio = item.ratioOf(totalCents);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: AppDimens.gapS),
            Expanded(
              child: Text(item.name, style: theme.textTheme.bodyMedium),
            ),
            Text(
              '${(ratio * 100).toStringAsFixed(0)}%',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(width: AppDimens.gapM),
            AmountText(cents: item.amountCents, fontSize: 14),
          ],
        ),
        const SizedBox(height: AppDimens.gapS),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: ratio.clamp(0.0, 1.0),
            minHeight: 4,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}

class _TopExpenses extends StatelessWidget {
  const _TopExpenses({required this.items});

  final List<NormalizedTransaction> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('大额支出 TOP ${items.length}', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppDimens.gapM),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppDimens.gapS),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          item.merchant.isEmpty ? '未知商户' : item.merchant,
                          style: theme.textTheme.bodyMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (item.description.isNotEmpty)
                          Text(
                            item.description,
                            style: theme.textTheme.labelSmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  AmountText(
                    cents: item.amountCents,
                    type: TransactionType.expense,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _RecentTransactions extends StatelessWidget {
  const _RecentTransactions({required this.items});

  final List<NormalizedTransaction> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('最近交易', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppDimens.gapM),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppDimens.gapS),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          item.merchant.isEmpty ? '未知商户' : item.merchant,
                          style: theme.textTheme.bodyMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${dayKey(item.transactionTime)} · ${item.source.label}',
                          style: theme.textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ),
                  AmountText(
                    cents: item.amountCents,
                    type: item.transactionType,
                    showSign: true,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppDimens.gapXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.error_outline,
              color: theme.colorScheme.error,
              size: 36,
            ),
            const SizedBox(height: AppDimens.gapM),
            Text('读取数据失败', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppDimens.gapS),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
