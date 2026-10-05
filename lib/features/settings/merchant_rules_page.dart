import 'package:finance_hub/app/providers.dart';
import 'package:finance_hub/app/rule_providers.dart';
import 'package:finance_hub/app/theme/app_colors.dart';
import 'package:finance_hub/core/utils/date_range.dart';
import 'package:finance_hub/domain/entities/merchant_rule.dart';
import 'package:finance_hub/shared/widgets/app_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 商户记忆管理页。
///
/// 商户记忆是分类的**第一优先级** —— 用户在导入预览里把某个商户
/// 指定过分类后，之后该商户的交易会自动沿用。
/// 这一页让用户能看到并管理这些记忆（否则会变成"黑盒"）。
class MerchantRulesPage extends ConsumerStatefulWidget {
  const MerchantRulesPage({super.key});

  @override
  ConsumerState<MerchantRulesPage> createState() => _MerchantRulesPageState();
}

class _MerchantRulesPageState extends ConsumerState<MerchantRulesPage> {
  final TextEditingController _searchController = TextEditingController();
  String _keyword = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final memories = ref.watch(merchantRulesProvider);
    final names = ref.watch(categoryNameMapProvider).value ?? const <int, String>{};

    return Scaffold(
      appBar: AppBar(
        title: const Text('商户记忆'),
        actions: <Widget>[
          IconButton(
            tooltip: '清空全部记忆',
            onPressed: () => _clearAll(),
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: memories.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stack) =>
            EmptyState(title: '读取失败', description: '$error'),
        data: (List<MerchantRule> all) {
          if (all.isEmpty) {
            return const EmptyState(
              title: '还没有商户记忆',
              description: '在导入预览里把某笔交易的分类改一下，'
                  '这个商户就会被记住，以后自动归类。',
            );
          }

          final filtered = _keyword.isEmpty
              ? all
              : all
                  .where((rule) =>
                      rule.merchantDisplay.toLowerCase().contains(_keyword))
                  .toList(growable: false);

          return Column(
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
                  decoration: InputDecoration(
                    hintText: '搜索商户（共 ${all.length} 个）',
                    prefixIcon: const Icon(Icons.search, size: 20),
                  ),
                  onChanged: (value) =>
                      setState(() => _keyword = value.trim().toLowerCase()),
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? const EmptyState(title: '没有匹配的商户')
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(
                          AppDimens.pagePadding,
                          0,
                          AppDimens.pagePadding,
                          AppDimens.gapXl,
                        ),
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: AppDimens.gapS),
                        itemBuilder: (context, index) {
                          final rule = filtered[index];
                          return _MerchantTile(
                            rule: rule,
                            categoryLabel: _labelOf(rule, names),
                            onDelete: () => _forget(rule),
                          );
                        },
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppDimens.pagePadding,
                  0,
                  AppDimens.pagePadding,
                  AppDimens.gapL,
                ),
                child: Text(
                  '商户记忆优先级最高，会盖过关键词规则。',
                  style: theme.textTheme.labelSmall,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  String _labelOf(MerchantRule rule, Map<int, String> names) {
    final top = names[rule.categoryId] ?? '未知分类';
    final sub =
        rule.subcategoryId == null ? null : names[rule.subcategoryId!];
    return sub == null || sub.isEmpty ? top : '$top / $sub';
  }

  Future<void> _forget(MerchantRule rule) async {
    await ref.read(ruleRepositoryProvider).forgetMerchant(rule.key);
    _refresh();
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('清空全部商户记忆'),
        content: const Text(
          '清空后，已记住的商户不再自动归类。\n'
          '已经分好类的历史账单不受影响，除非你之后重新分类。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await ref.read(ruleRepositoryProvider).clearMerchantRules();
    _refresh();
  }

  void _refresh() {
    ref
      ..invalidate(merchantRulesProvider)
      ..invalidate(categorizationEngineProvider);
  }
}

class _MerchantTile extends StatelessWidget {
  const _MerchantTile({
    required this.rule,
    required this.categoryLabel,
    required this.onDelete,
  });

  final MerchantRule rule;
  final String categoryLabel;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final last = rule.lastAppliedAt;

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
                  rule.merchantDisplay,
                  style: theme.textTheme.bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '→ $categoryLabel'
                  '${rule.source == null ? '' : ' · 仅限${rule.source!.label}'}'
                  '${last == null ? '' : ' · 最后设置 ${dayKey(last)}'}',
                  style: theme.textTheme.labelSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '忘记',
            onPressed: onDelete,
            icon: const Icon(Icons.close, size: 18),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
