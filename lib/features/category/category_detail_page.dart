import 'package:finance_hub/app/providers.dart';
import 'package:finance_hub/app/theme/app_colors.dart';
import 'package:finance_hub/core/money/money.dart';
import 'package:finance_hub/core/utils/date_range.dart';
import 'package:finance_hub/domain/entities/statistics.dart';
import 'package:finance_hub/features/merchant/merchant_detail_page.dart';
import 'package:finance_hub/shared/widgets/amount_text.dart';
import 'package:finance_hub/shared/widgets/app_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 分类下钻页 —— brief 第 14 条。
///
/// 三层结构：
/// ```
/// 一级分类（餐饮 ¥826）
///   ↓ 点击
/// 二级分类（外卖 ¥312 / 正餐 ¥184 / 便利店 ¥126 …）
///   ↓ 点击
/// 商户（美团 ¥182 / 饿了么 ¥96 …）
///   ↓ 点击
/// 商户详情（累计 / 次数 / 均值 / 月度趋势）
/// ```
class CategoryDetailPage extends ConsumerStatefulWidget {
  const CategoryDetailPage({
    required this.categoryId,
    required this.categoryName,
    super.key,
  });

  final int categoryId;
  final String categoryName;

  @override
  ConsumerState<CategoryDetailPage> createState() => _CategoryDetailPageState();
}

class _CategoryDetailPageState extends ConsumerState<CategoryDetailPage> {
  int? _subcategoryId;
  String? _subcategoryName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final month = ref.watch(selectedMonthProvider);
    final range = DateRanges.monthOf(month);

    final query = _CategoryQuery(
      categoryId: widget.categoryId,
      subcategoryId: _subcategoryId,
      fromMillis: range.startMillis,
      toMillis: range.endMillis,
    );

    final subcategories = ref.watch(_subcategoryTotalsProvider(query));
    final merchants = ref.watch(_merchantTotalsProvider(query));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _subcategoryId == null
              ? widget.categoryName
              : '${widget.categoryName} / ${_subcategoryName ?? ''}',
          overflow: TextOverflow.ellipsis,
        ),
        leading: _subcategoryId == null
            ? null
            : IconButton(
                tooltip: '返回${widget.categoryName}',
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() {
                  _subcategoryId = null;
                  _subcategoryName = null;
                }),
              ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppDimens.pagePadding,
          AppDimens.gapS,
          AppDimens.pagePadding,
          AppDimens.gapXl,
        ),
        children: <Widget>[
          _TotalHeader(
            title: _subcategoryId == null
                ? widget.categoryName
                : '${widget.categoryName} / ${_subcategoryName ?? ''}',
            subtitle: '${month.year}年${month.month}月',
            subcategories: subcategories.value,
          ),
          const SizedBox(height: AppDimens.gapL),

          if (_subcategoryId == null) ...<Widget>[
            SectionHeader(
              '二级分类',
              trailing: Text(
                '点击查看商户',
                style: theme.textTheme.labelSmall,
              ),
            ),
            _SubcategoryList(
              data: subcategories.value ?? const <CategoryTotal>[],
              loading: subcategories.isLoading,
              onTap: (item) => setState(() {
                _subcategoryId = item.categoryId;
                _subcategoryName = item.name;
              }),
            ),
          ] else ...<Widget>[
            SectionHeader('商户', trailing: Text('点击查看详情', style: theme.textTheme.labelSmall)),
            _MerchantList(
              data: merchants.value ?? const <MerchantStat>[],
              loading: merchants.isLoading,
            ),
          ],
        ],
      ),
    );
  }
}

/// 分类下钻的查询参数。
class _CategoryQuery {
  const _CategoryQuery({
    required this.categoryId,
    required this.subcategoryId,
    required this.fromMillis,
    required this.toMillis,
  });

  final int categoryId;
  final int? subcategoryId;
  final int fromMillis;
  final int toMillis;

  @override
  bool operator ==(Object other) =>
      other is _CategoryQuery &&
      other.categoryId == categoryId &&
      other.subcategoryId == subcategoryId &&
      other.fromMillis == fromMillis &&
      other.toMillis == toMillis;

  @override
  int get hashCode =>
      Object.hash(categoryId, subcategoryId, fromMillis, toMillis);
}

final _subcategoryTotalsProvider =
    FutureProvider.family<List<CategoryTotal>, _CategoryQuery>(
  (Ref ref, _CategoryQuery query) async {
    final dao = ref.watch(analyticsDaoProvider);
    return dao.subcategoryTotals(
      parentCategoryId: query.categoryId,
      fromMillis: query.fromMillis,
      toMillis: query.toMillis,
    );
  },
);

final _merchantTotalsProvider =
    FutureProvider.family<List<MerchantStat>, _CategoryQuery>(
  (Ref ref, _CategoryQuery query) async {
    final dao = ref.watch(analyticsDaoProvider);
    return dao.merchantTotals(
      fromMillis: query.fromMillis,
      toMillis: query.toMillis,
      categoryId: query.subcategoryId == null ? query.categoryId : null,
      subcategoryId: query.subcategoryId,
      limit: 50,
    );
  },
);

class _TotalHeader extends StatelessWidget {
  const _TotalHeader({
    required this.title,
    required this.subtitle,
    required this.subcategories,
  });

  final String title;
  final String subtitle;
  final List<CategoryTotal>? subcategories;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final list = subcategories;
    final total = list?.fold<int>(0, (sum, item) => sum + item.amountCents);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(subtitle, style: theme.textTheme.bodySmall),
          const SizedBox(height: AppDimens.gapS),
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: AppDimens.gapS),
          Text(
            total == null ? '统计中…' : formatCents(total, withSymbol: true),
            style: theme.textTheme.displaySmall,
          ),
          if (list != null && list.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppDimens.gapXs),
            Text(
              '共 ${list.fold<int>(0, (sum, item) => sum + item.transactionCount)} 笔',
              style: theme.textTheme.labelSmall,
            ),
          ],
        ],
      ),
    );
  }
}

class _SubcategoryList extends StatelessWidget {
  const _SubcategoryList({
    required this.data,
    required this.loading,
    required this.onTap,
  });

  final List<CategoryTotal> data;
  final bool loading;
  final ValueChanged<CategoryTotal> onTap;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.all(AppDimens.gapXl),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (data.isEmpty) {
      return const AppCard(
        child: Text('该分类下暂无明细，可能是账单里没有二级分类信息'),
      );
    }
    final total = data.fold<int>(0, (sum, item) => sum + item.amountCents);

    return Column(
      children: <Widget>[
        for (final item in data) ...<Widget>[
          _DrillRow(
            name: item.name,
            subtitle: '${item.transactionCount} 笔',
            amountCents: item.amountCents,
            ratio: item.ratioOf(total),
            color: AppColors.parseHex(
              item.color,
              fallback: Theme.of(context).colorScheme.primary,
            ),
            onTap: () => onTap(item),
          ),
          const SizedBox(height: AppDimens.gapS),
        ],
      ],
    );
  }
}

class _MerchantList extends StatelessWidget {
  const _MerchantList({required this.data, required this.loading});

  final List<MerchantStat> data;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.all(AppDimens.gapXl),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (data.isEmpty) {
      return const AppCard(child: Text('该分类下暂无商户记录'));
    }
    final total = data.fold<int>(0, (sum, item) => sum + item.totalCents);

    return Column(
      children: <Widget>[
        for (final item in data) ...<Widget>[
          _DrillRow(
            name: item.merchant,
            subtitle: '${item.transactionCount} 笔 · 均值 '
                '${formatCents(item.averageCents, withSymbol: true)}',
            amountCents: item.totalCents,
            ratio: total == 0 ? 0 : item.totalCents / total,
            color: Theme.of(context).colorScheme.primary,
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                builder: (_) => MerchantDetailPage(merchant: item.merchant),
              ),
            ),
          ),
          const SizedBox(height: AppDimens.gapS),
        ],
      ],
    );
  }
}

class _DrillRow extends StatelessWidget {
  const _DrillRow({
    required this.name,
    required this.subtitle,
    required this.amountCents,
    required this.ratio,
    required this.color,
    required this.onTap,
  });

  final String name;
  final String subtitle;
  final int amountCents;
  final double ratio;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.gapM,
        vertical: AppDimens.gapM,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  name,
                  style: theme.textTheme.bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              AmountText(cents: amountCents, fontSize: 14),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(subtitle, style: theme.textTheme.labelSmall),
              ),
              Text(
                '${(ratio * 100).toStringAsFixed(0)}%',
                style: theme.textTheme.labelSmall,
              ),
            ],
          ),
          const SizedBox(height: AppDimens.gapS),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: ratio.clamp(0.0, 1.0),
              minHeight: 3,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }
}
