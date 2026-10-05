import 'package:finance_hub/app/providers.dart';
import 'package:finance_hub/app/theme/app_colors.dart';
import 'package:finance_hub/core/utils/date_range.dart';
import 'package:finance_hub/domain/entities/normalized_transaction.dart';
import 'package:finance_hub/domain/enums/bill_source.dart';
import 'package:finance_hub/domain/enums/transaction_type.dart';
import 'package:finance_hub/features/import/import_entry.dart';
import 'package:finance_hub/shared/widgets/amount_text.dart';
import 'package:finance_hub/shared/widgets/app_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 账单明细页 —— brief 第 18/19 条。
///
/// 搜索 / 来源筛选 / 类型筛选 / 时间范围 / 排序全部**下推到 SQL**。
class BillsPage extends ConsumerStatefulWidget {
  const BillsPage({super.key});

  @override
  ConsumerState<BillsPage> createState() => _BillsPageState();
}

class _BillsPageState extends ConsumerState<BillsPage> {
  final TextEditingController _searchController = TextEditingController();
  String _keyword = '';
  BillSource? _source;
  TransactionType? _type;
  _RangePreset _range = _RangePreset.month;
  bool _sortByAmount = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  DateRange _resolveRange() {
    final now = DateTime.now();
    switch (_range) {
      case _RangePreset.today:
        return DateRanges.day(now);
      case _RangePreset.week:
        return DateRanges.week(now);
      case _RangePreset.month:
        return DateRanges.monthOf(now);
      case _RangePreset.year:
        return DateRanges.yearOf(now);
      case _RangePreset.all:
        return DateRange(
          DateTime(2000),
          DateTime(DateTime.now().year + 1),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final range = _resolveRange();
    final dao = ref.watch(analyticsDaoProvider);
    final bills = ref.watch(_billsQueryProvider(_BillQuery(
      keyword: _keyword,
      source: _source,
      type: _type,
      fromMillis: range.startMillis,
      toMillis: range.endMillis,
      sortByAmountDesc: _sortByAmount,
    )));

    return Scaffold(
      appBar: AppBar(
        title: const Text('账单明细'),
        actions: <Widget>[
          IconButton(
            tooltip: _sortByAmount ? '按时间排序' : '按金额排序',
            onPressed: () => setState(() => _sortByAmount = !_sortByAmount),
            icon: Icon(
              _sortByAmount ? Icons.sort : Icons.swap_vert,
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => ImportEntry.open(context, ref),
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppDimens.pagePadding,
              AppDimens.gapS,
              AppDimens.pagePadding,
              AppDimens.gapS,
            ),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: '搜索商户 / 商品 / 备注',
                prefixIcon: Icon(Icons.search, size: 20),
              ),
              onChanged: (value) => setState(() => _keyword = value),
            ),
          ),
          _FilterChips(
            source: _source,
            type: _type,
            range: _range,
            onSourceChanged: (value) => setState(() => _source = value),
            onTypeChanged: (value) => setState(() => _type = value),
            onRangeChanged: (value) => setState(() => _range = value),
          ),
          const SizedBox(height: AppDimens.gapS),
          Expanded(
            child: bills.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (Object error, StackTrace stack) => EmptyState(
                title: '查询失败',
                description: '$error',
              ),
              data: (List<NormalizedTransaction> items) {
                if (items.isEmpty) {
                  return const EmptyState(
                    title: '没有符合条件的交易',
                    description: '试试放宽筛选条件，或导入新的账单',
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                    AppDimens.pagePadding,
                    0,
                    AppDimens.pagePadding,
                    88,
                  ),
                  itemCount: items.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: AppDimens.gapS),
                  itemBuilder: (context, index) =>
                      _BillTile(transaction: items[index]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// 查询参数（作为 family provider 的 key，必须可比较）。
class _BillQuery {
  const _BillQuery({
    required this.keyword,
    required this.source,
    required this.type,
    required this.fromMillis,
    required this.toMillis,
    required this.sortByAmountDesc,
  });

  final String keyword;
  final BillSource? source;
  final TransactionType? type;
  final int fromMillis;
  final int toMillis;
  final bool sortByAmountDesc;

  @override
  bool operator ==(Object other) =>
      other is _BillQuery &&
      other.keyword == keyword &&
      other.source == source &&
      other.type == type &&
      other.fromMillis == fromMillis &&
      other.toMillis == toMillis &&
      other.sortByAmountDesc == sortByAmountDesc;

  @override
  int get hashCode => Object.hash(
        keyword,
        source,
        type,
        fromMillis,
        toMillis,
        sortByAmountDesc,
      );
}

final _billsQueryProvider =
    FutureProvider.family<List<NormalizedTransaction>, _BillQuery>(
  (Ref ref, _BillQuery query) async {
    final dao = ref.watch(analyticsDaoProvider);
    return dao.search(
      keyword: query.keyword,
      source: query.source?.code,
      transactionType: query.type?.code,
      fromMillis: query.fromMillis,
      toMillis: query.toMillis,
      sortByAmountDesc: query.sortByAmountDesc,
      limit: 300,
    );
  },
);

enum _RangePreset {
  today('今天'),
  week('本周'),
  month('本月'),
  year('今年'),
  all('全部');

  const _RangePreset(this.label);

  final String label;
}

class _FilterChips extends StatelessWidget {
  const _FilterChips({
    required this.source,
    required this.type,
    required this.range,
    required this.onSourceChanged,
    required this.onTypeChanged,
    required this.onRangeChanged,
  });

  final BillSource? source;
  final TransactionType? type;
  final _RangePreset range;
  final ValueChanged<BillSource?> onSourceChanged;
  final ValueChanged<TransactionType?> onTypeChanged;
  final ValueChanged<_RangePreset> onRangeChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: AppDimens.pagePadding),
      child: Row(
        children: <Widget>[
          for (final preset in _RangePreset.values) ...<Widget>[
            ChoiceChip(
              label: Text(preset.label),
              selected: range == preset,
              onSelected: (_) => onRangeChanged(preset),
            ),
            const SizedBox(width: AppDimens.gapS),
          ],
          const SizedBox(width: AppDimens.gapS),
          FilterChip(
            label: Text(source?.label ?? '全部来源'),
            selected: source != null,
            onSelected: (_) => onSourceChanged(
              source == null ? BillSource.wechat : null,
            ),
          ),
          const SizedBox(width: AppDimens.gapS),
          FilterChip(
            label: Text(type?.label ?? '全部类型'),
            selected: type != null,
            onSelected: (_) =>
                onTypeChanged(type == null ? TransactionType.expense : null),
          ),
        ],
      ),
    );
  }
}

class _BillTile extends StatelessWidget {
  const _BillTile({required this.transaction});

  final NormalizedTransaction transaction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tx = transaction;

    return AppCard(
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
                  tx.merchant.isEmpty ? '未知商户' : tx.merchant,
                  style: theme.textTheme.bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${dayKey(tx.transactionTime)} · ${tx.source.label}'
                  '${tx.description.isEmpty ? '' : ' · ${tx.description}'}',
                  style: theme.textTheme.labelSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          AmountText(
            cents: tx.amountCents,
            type: tx.transactionType,
            showSign: true,
          ),
        ],
      ),
    );
  }
}
