import 'package:finance_hub/app/providers.dart';
import 'package:finance_hub/app/theme/app_colors.dart';
import 'package:finance_hub/core/money/money.dart';
import 'package:finance_hub/domain/entities/budget.dart';
import 'package:finance_hub/domain/entities/category.dart';
import 'package:finance_hub/shared/widgets/app_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 预算页 —— brief 第 20 条。
///
/// 设计要点：**不做刺眼的红色警报**。
/// 接近上限（≥80%）与超出上限都用低饱和琥珀色表达，
/// 通过进度条与文案传达信息，而不是靠大红大绿制造焦虑。
class BudgetPage extends ConsumerWidget {
  const BudgetPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final progress = ref.watch(budgetProgressProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('预算')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context, ref, null),
        icon: const Icon(Icons.add),
        label: const Text('添加预算'),
      ),
      body: progress.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stack) =>
            EmptyState(title: '读取预算失败', description: '$error'),
        data: (List<BudgetProgress> items) {
          if (items.isEmpty) {
            return EmptyState(
              title: '还没有设置预算',
              description: '给「餐饮」「购物」这类分类设一个月度上限，'
                  '之后每次看首页就知道还剩多少。',
              action: FilledButton.icon(
                onPressed: () => _openEditor(context, ref, null),
                icon: const Icon(Icons.add),
                label: const Text('添加预算'),
              ),
            );
          }

          final over = items.where((item) => item.isOver).length;
          final near =
              items.where((item) => item.alertLevel == 1).length;

          return ListView(
            padding: const EdgeInsets.fromLTRB(
              AppDimens.pagePadding,
              AppDimens.gapS,
              AppDimens.pagePadding,
              88,
            ),
            children: <Widget>[
              if (over > 0 || near > 0) ...<Widget>[
                _AlertSummary(over: over, near: near),
                const SizedBox(height: AppDimens.gapL),
              ],
              for (final item in items) ...<Widget>[
                _BudgetTile(
                  progress: item,
                  onEdit: () => _openEditor(context, ref, item),
                  onDelete: () => _confirmDelete(context, ref, item),
                ),
                const SizedBox(height: AppDimens.gapM),
              ],
              const SizedBox(height: AppDimens.gapS),
              Text(
                '预算是本机数据，不会同步到任何服务器。',
                style: theme.textTheme.labelSmall,
                textAlign: TextAlign.center,
              ),
            ],
          );
        },
      ),
    );
  }

  static Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    BudgetProgress item,
  ) async {
    final id = item.budget.id;
    if (id == null) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除预算'),
        content: Text('确定删除「${item.categoryName}」的预算吗？'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await ref.read(budgetRepositoryProvider).remove(id);
    ref.invalidate(budgetProgressProvider);
  }

  static Future<void> _openEditor(
    BuildContext context,
    WidgetRef ref,
    BudgetProgress? existing,
  ) async {
    final result = await showModalBottomSheet<_BudgetDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _BudgetEditorSheet(existing: existing),
    );
    if (result == null) {
      return;
    }

    final repository = ref.read(budgetRepositoryProvider);
    await repository.upsert(
      Budget(
        id: existing?.budget.id,
        categoryId: result.categoryId,
        amountCents: result.amountCents,
        period: result.period,
        startDate: existing?.budget.startDate ?? DateTime.now(),
        isActive: true,
      ),
    );
    ref.invalidate(budgetProgressProvider);
  }
}

/// 预算编辑结果。
class _BudgetDraft {
  const _BudgetDraft({
    required this.categoryId,
    required this.amountCents,
    required this.period,
  });

  final int? categoryId;
  final int amountCents;
  final BudgetPeriod period;
}

class _AlertSummary extends StatelessWidget {
  const _AlertSummary({required this.over, required this.near});

  final int over;
  final int near;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final warning = isDark ? AppColors.darkWarning : AppColors.lightWarning;

    final parts = <String>[
      if (over > 0) '$over 项已超出预算',
      if (near > 0) '$near 项接近上限',
    ];

    return AppCard(
      child: Row(
        children: <Widget>[
          Icon(Icons.info_outline, size: 18, color: warning),
          const SizedBox(width: AppDimens.gapM),
          Expanded(
            child: Text(
              parts.join('，'),
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _BudgetTile extends StatelessWidget {
  const _BudgetTile({
    required this.progress,
    required this.onEdit,
    required this.onDelete,
  });

  final BudgetProgress progress;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // 低饱和配色：正常用主色，接近/超出用琥珀
    final Color barColor;
    switch (progress.alertLevel) {
      case 0:
        barColor = theme.colorScheme.primary;
      case 1:
        barColor = isDark ? AppColors.darkWarning : AppColors.lightWarning;
      default:
        barColor = isDark ? AppColors.darkExpense : AppColors.lightExpense;
    }

    final subtitle = progress.subcategoryName == null
        ? progress.budget.period.label
        : '${progress.budget.period.label} · ${progress.subcategoryName}';

    return AppCard(
      onTap: onEdit,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      progress.categoryName,
                      style: theme.textTheme.titleMedium,
                    ),
                    Text(subtitle, style: theme.textTheme.labelSmall),
                  ],
                ),
              ),
              Text(
                '${formatCents(progress.usedCents)} / '
                '${formatCents(progress.limitCents)}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: AppDimens.gapS),
              IconButton(
                tooltip: '删除',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline, size: 18),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: AppDimens.gapM),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress.ratio.clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(barColor),
            ),
          ),
          const SizedBox(height: AppDimens.gapS),
          Text(
            progress.isOver
                ? '已超出 ${formatCents(progress.usedCents - progress.limitCents, withSymbol: true)}'
                : '剩余 ${formatCents(progress.remainingCents, withSymbol: true)}'
                    '（已用 ${(progress.ratio * 100).toStringAsFixed(0)}%）',
            style: theme.textTheme.labelSmall?.copyWith(
              color: progress.isOver ? barColor : null,
              fontWeight: progress.isOver ? FontWeight.w600 : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// 预算编辑底部弹层。
class _BudgetEditorSheet extends ConsumerStatefulWidget {
  const _BudgetEditorSheet({this.existing});

  final BudgetProgress? existing;

  @override
  ConsumerState<_BudgetEditorSheet> createState() => _BudgetEditorSheetState();
}

class _BudgetEditorSheetState extends ConsumerState<_BudgetEditorSheet> {
  late final TextEditingController _amountController;
  int? _categoryId;
  BudgetPeriod _period = BudgetPeriod.monthly;
  String? _error;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _categoryId = existing?.budget.categoryId;
    _period = existing?.budget.period ?? BudgetPeriod.monthly;
    _amountController = TextEditingController(
      text: existing == null
          ? ''
          : (existing.budget.amountCents / 100).toStringAsFixed(2),
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categories = ref.watch(allCategoriesProvider);
    final topLevel = (categories.value ?? const <Category>[])
        .where((item) => item.isTopLevel)
        .toList(growable: false);

    return Padding(
      padding: EdgeInsets.only(
        left: AppDimens.pagePadding,
        right: AppDimens.pagePadding,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppDimens.gapXl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            widget.existing == null ? '添加预算' : '编辑预算',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: AppDimens.gapL),
          Text('分类', style: theme.textTheme.labelSmall),
          const SizedBox(height: AppDimens.gapS),
          if (categories.isLoading)
            const LinearProgressIndicator(minHeight: 2)
          else
            Wrap(
              spacing: AppDimens.gapS,
              runSpacing: AppDimens.gapS,
              children: <Widget>[
                ChoiceChip(
                  label: const Text('总预算'),
                  selected: _categoryId == null,
                  onSelected: (_) => setState(() => _categoryId = null),
                ),
                for (final category in topLevel)
                  ChoiceChip(
                    label: Text(category.name),
                    selected: _categoryId == category.id,
                    onSelected: (_) =>
                        setState(() => _categoryId = category.id),
                  ),
              ],
            ),
          const SizedBox(height: AppDimens.gapL),
          Text('金额（元）', style: theme.textTheme.labelSmall),
          const SizedBox(height: AppDimens.gapS),
          TextField(
            controller: _amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              hintText: '例如 800',
              errorText: _error,
              prefixText: '\u00A5 ',
            ),
          ),
          const SizedBox(height: AppDimens.gapL),
          Text('周期', style: theme.textTheme.labelSmall),
          const SizedBox(height: AppDimens.gapS),
          SegmentedButton<BudgetPeriod>(
            segments: <ButtonSegment<BudgetPeriod>>[
              for (final period in BudgetPeriod.values)
                ButtonSegment<BudgetPeriod>(
                  value: period,
                  label: Text(period.label),
                ),
            ],
            selected: <BudgetPeriod>{_period},
            onSelectionChanged: (selection) =>
                setState(() => _period = selection.first),
          ),
          const SizedBox(height: AppDimens.gapXl),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
              ),
              const SizedBox(width: AppDimens.gapM),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: _submit,
                  child: const Text('保存'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _submit() {
    final cents = parseMoneyToCents(_amountController.text);
    if (cents == null || cents <= 0) {
      setState(() => _error = '请输入大于 0 的金额');
      return;
    }
    Navigator.of(context).pop(
      _BudgetDraft(
        categoryId: _categoryId,
        amountCents: cents,
        period: _period,
      ),
    );
  }
}
