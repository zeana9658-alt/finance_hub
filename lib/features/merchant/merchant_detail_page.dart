import 'package:finance_hub/app/providers.dart';
import 'package:finance_hub/app/theme/app_colors.dart';
import 'package:finance_hub/core/money/money.dart';
import 'package:finance_hub/core/utils/date_range.dart';
import 'package:finance_hub/domain/entities/normalized_transaction.dart';
import 'package:finance_hub/domain/entities/statistics.dart';
import 'package:finance_hub/shared/widgets/amount_text.dart';
import 'package:finance_hub/shared/widgets/app_card.dart';
import 'package:finance_hub/shared/widgets/charts/monthly_trend_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 商户分析页 —— brief 第 19 条。
///
/// 展示：累计消费 / 交易次数 / 平均单笔 / 最近一次 / 月度趋势 / 该商户的流水。
class MerchantDetailPage extends ConsumerWidget {
  const MerchantDetailPage({required this.merchant, super.key});

  final String merchant;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final stat = ref.watch(_merchantStatProvider(merchant));
    final trend = ref.watch(_merchantTrendProvider(merchant));
    final transactions = ref.watch(_merchantTransactionsProvider(merchant));

    return Scaffold(
      appBar: AppBar(
        title: Text(merchant, overflow: TextOverflow.ellipsis),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppDimens.pagePadding,
          AppDimens.gapS,
          AppDimens.pagePadding,
          AppDimens.gapXl,
        ),
        children: <Widget>[
          stat.when(
            loading: () => const AppCard(
              child: SizedBox(
                height: 80,
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
            error: (Object error, StackTrace stack) =>
                AppCard(child: Text('读取失败：$error')),
            data: (MerchantStat? value) {
              if (value == null) {
                return const AppCard(child: Text('没有找到该商户的消费记录'));
              }
              return AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('累计消费', style: theme.textTheme.bodySmall),
                    const SizedBox(height: AppDimens.gapS),
                    Text(
                      formatCents(value.totalCents, withSymbol: true),
                      style: theme.textTheme.displaySmall,
                    ),
                    const SizedBox(height: AppDimens.gapL),
                    const Divider(height: 1),
                    const SizedBox(height: AppDimens.gapL),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: _MiniFact(
                            label: '交易次数',
                            value: '${value.transactionCount} 次',
                          ),
                        ),
                        Expanded(
                          child: _MiniFact(
                            label: '平均单笔',
                            value: formatCents(
                              value.averageCents,
                              withSymbol: true,
                            ),
                          ),
                        ),
                        Expanded(
                          child: _MiniFact(
                            label: '最近一次',
                            value: dayKey(value.lastTransactionAt),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: AppDimens.gapL),
          SectionHeader('月度趋势'),
          AppCard(
            child: trend.when(
              loading: () => const SizedBox(
                height: 180,
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (Object error, StackTrace stack) => Text('读取失败：$error'),
              data: (List<MonthlyTotal> value) => MonthlyTrendChart(data: value),
            ),
          ),
          const SizedBox(height: AppDimens.gapL),
          SectionHeader('该商户的流水'),
          transactions.when(
            loading: () => const AppCard(
              child: SizedBox(
                height: 60,
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
            error: (Object error, StackTrace stack) =>
                AppCard(child: Text('读取失败：$error')),
            data: (List<NormalizedTransaction> items) {
              if (items.isEmpty) {
                return const AppCard(child: Text('暂无记录'));
              }
              return Column(
                children: <Widget>[
                  for (final item in items) ...<Widget>[
                    AppCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppDimens.gapM,
                        vertical: AppDimens.gapM,
                      ),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  item.description.isEmpty
                                      ? '（无商品说明）'
                                      : item.description,
                                  style: theme.textTheme.bodyMedium,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  '${dayKey(item.transactionTime)} · '
                                  '${item.source.label}',
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
                    const SizedBox(height: AppDimens.gapS),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MiniFact extends StatelessWidget {
  const _MiniFact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: theme.textTheme.labelSmall),
        const SizedBox(height: 2),
        Text(
          value,
          style: theme.textTheme.titleMedium,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

// ───────────────────── 商户相关 provider ─────────────────────

final _merchantStatProvider =
    FutureProvider.family<MerchantStat?, String>((Ref ref, String merchant) async {
  final dao = ref.watch(analyticsDaoProvider);
  return dao.merchantStat(merchant);
});

final _merchantTrendProvider =
    FutureProvider.family<List<MonthlyTotal>, String>((Ref ref, String merchant) async {
  final dao = ref.watch(analyticsDaoProvider);
  final now = DateTime.now();
  final start = DateTime(now.year, now.month - 11);
  final end = DateRanges.monthOf(now);
  final sparse = await dao.merchantMonthlyTotals(
    merchant: merchant,
    fromMillis: start.millisecondsSinceEpoch,
    toMillis: end.endMillis,
  );
  return MonthlyTotal.fillGaps(
    sparse,
    from: start,
    to: DateTime(now.year, now.month),
  );
});

final _merchantTransactionsProvider =
    FutureProvider.family<List<NormalizedTransaction>, String>(
  (Ref ref, String merchant) async {
    final dao = ref.watch(analyticsDaoProvider);
    return dao.search(keyword: merchant, limit: 50);
  },
);
