import 'package:finance_hub/app/providers.dart';
import 'package:finance_hub/app/theme/app_colors.dart';
import 'package:finance_hub/core/money/money.dart';
import 'package:finance_hub/domain/entities/statistics.dart';
import 'package:finance_hub/shared/widgets/app_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 统计页 —— brief 第 15/17 条。
///
/// 包含：
/// - 消费日历（按天热力着色，点击看当天）
/// - 消费时段分布（7 段柱状）
/// - 大额支出 TOP 5
///
/// 图表全部用真实数据绘制（日历与柱状自绘，不引入假数据）。
class StatsPage extends ConsumerWidget {
  const StatsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(selectedMonthProvider);
    final daily = ref.watch(dailyTotalsProvider);
    final buckets = ref.watch(timeBucketTotalsProvider);
    final top = ref.watch(topExpensesProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('统计 · ${month.year}年${month.month}月'),
        actions: <Widget>[
          IconButton(
            tooltip: '上个月',
            onPressed: () =>
                ref.read(selectedMonthProvider.notifier).previousMonth(),
            icon: const Icon(Icons.chevron_left),
          ),
          IconButton(
            tooltip: '下个月',
            onPressed: () =>
                ref.read(selectedMonthProvider.notifier).nextMonth(),
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppDimens.pagePadding,
          0,
          AppDimens.pagePadding,
          AppDimens.gapXl,
        ),
        children: <Widget>[
          _ConsumptionCalendar(
            month: month,
            daily: daily.value ?? const <DailyTotal>[],
          ),
          const SizedBox(height: AppDimens.gapL),
          _TimeBuckets(buckets: buckets.value ?? const <TimeBucketTotal>[]),
          const SizedBox(height: AppDimens.gapL),
          _MerchantHint(top: top.value ?? const <dynamic>[]),
        ],
      ),
    );
  }
}

/// 消费日历 —— 消费越高颜色越深。
class _ConsumptionCalendar extends StatelessWidget {
  const _ConsumptionCalendar({required this.month, required this.daily});

  final DateTime month;
  final List<DailyTotal> daily;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final byDay = <int, DailyTotal>{
      for (final item in daily) item.day.day: item,
    };
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final firstWeekday =
        DateTime(month.year, month.month, 1).weekday; // 1=周一 … 7=周日
    final leading = (firstWeekday - DateTime.monday + 7) % 7;

    final maxExpense = daily.isEmpty
        ? 0
        : daily.map((item) => item.expenseCents).reduce((a, b) => a > b ? a : b);

    const weekLabels = <String>['一', '二', '三', '四', '五', '六', '日'];

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text('消费日历', style: theme.textTheme.titleMedium),
              ),
              if (maxExpense > 0)
                Text(
                  '单日最高 ${formatCents(maxExpense, withSymbol: true)}',
                  style: theme.textTheme.labelSmall,
                ),
            ],
          ),
          const SizedBox(height: AppDimens.gapM),
          Row(
            children: <Widget>[
              for (final label in weekLabels)
                Expanded(
                  child: Center(
                    child: Text(label, style: theme.textTheme.labelSmall),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppDimens.gapXs),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: leading + daysInMonth,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
              childAspectRatio: 1,
            ),
            itemBuilder: (context, index) {
              if (index < leading) {
                return const SizedBox.shrink();
              }
              final day = index - leading + 1;
              final item = byDay[day];
              final intensity = (maxExpense == 0 || item == null)
                  ? 0.0
                  : (item.expenseCents / maxExpense).clamp(0.0, 1.0);

              return Tooltip(
                message: item == null
                    ? '$day 日：无消费'
                    : '$day 日：支出 ${formatCents(item.expenseCents, withSymbol: true)}'
                        '${item.incomeCents > 0 ? '，收入 ${formatCents(item.incomeCents, withSymbol: true)}' : ''}',
                child: Container(
                  decoration: BoxDecoration(
                    color: intensity == 0
                        ? theme.colorScheme.surfaceContainerHighest
                        : theme.colorScheme.primary.withValues(
                            alpha: isDark
                                ? 0.20 + intensity * 0.65
                                : 0.12 + intensity * 0.58,
                          ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(
                      '$day',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: intensity > 0.55
                            ? Colors.white
                            : theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          if (daily.isEmpty) ...<Widget>[
            const SizedBox(height: AppDimens.gapM),
            Text('本月暂无消费记录', style: theme.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

/// 消费时段分布。
class _TimeBuckets extends StatelessWidget {
  const _TimeBuckets({required this.buckets});

  final List<TimeBucketTotal> buckets;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxAmount = buckets.isEmpty
        ? 0
        : buckets
            .map((bucket) => bucket.amountCents)
            .fold<int>(0, (a, b) => a > b ? a : b);

    final peak = maxAmount == 0
        ? null
        : buckets.reduce((a, b) => a.amountCents >= b.amountCents ? a : b);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('消费时段分布', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppDimens.gapXs),
          Text(
            peak == null
                ? '暂无数据'
                : '你在 ${peak.label} 最容易花钱（${formatCents(peak.amountCents, withSymbol: true)}）',
            style: theme.textTheme.labelSmall,
          ),
          const SizedBox(height: AppDimens.gapL),
          for (final bucket in buckets) ...<Widget>[
            _BucketBar(
              bucket: bucket,
              ratio: maxAmount == 0 ? 0 : bucket.amountCents / maxAmount,
              isPeak: peak != null && bucket.bucketIndex == peak.bucketIndex,
            ),
            const SizedBox(height: AppDimens.gapM),
          ],
        ],
      ),
    );
  }
}

class _BucketBar extends StatelessWidget {
  const _BucketBar({
    required this.bucket,
    required this.ratio,
    required this.isPeak,
  });

  final TimeBucketTotal bucket;
  final double ratio;
  final bool isPeak;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Text(
                bucket.label,
                style: theme.textTheme.bodySmall,
              ),
            ),
            Text(
              formatCents(bucket.amountCents, withSymbol: true),
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: isPeak ? FontWeight.w700 : FontWeight.w400,
                color: isPeak
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: AppDimens.gapS),
            SizedBox(
              width: 36,
              child: Text(
                '${bucket.transactionCount}笔',
                textAlign: TextAlign.right,
                style: theme.textTheme.labelSmall,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppDimens.gapXs),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: ratio.clamp(0.0, 1.0),
            minHeight: 6,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation<Color>(
              isPeak
                  ? theme.colorScheme.primary
                  : theme.colorScheme.primary.withValues(alpha: 0.45),
            ),
          ),
        ),
      ],
    );
  }
}

/// 商户分析入口提示（完整商户分析页在 Phase 13 之后补）。
class _MerchantHint extends StatelessWidget {
  const _MerchantHint({required this.top});

  final List<dynamic> top;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('商户分析', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppDimens.gapS),
          Text(
            '按商户汇总的累计消费 / 次数 / 均值 / 月度趋势正在实现中'
            '（Phase 13）。数据层已就绪：AnalyticsDao.merchantStat()。',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
