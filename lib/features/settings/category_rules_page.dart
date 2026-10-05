import 'package:finance_hub/app/providers.dart';
import 'package:finance_hub/app/rule_providers.dart';
import 'package:finance_hub/app/theme/app_colors.dart';
import 'package:finance_hub/domain/entities/category.dart';
import 'package:finance_hub/domain/entities/category_rule.dart';
import 'package:finance_hub/shared/widgets/app_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 分类规则管理页 —— brief 第 11 条。
///
/// 三件事：
/// 1. 规则可视化编辑（内置规则可改可禁用、不可删；自定义规则可增删改）
/// 2. 一键**重新分类历史账单**，且**绝不覆盖用户手动指定的分类**
/// 3. 规则命中次数统计（哪条规则在真正起作用）
class CategoryRulesPage extends ConsumerStatefulWidget {
  const CategoryRulesPage({super.key});

  @override
  ConsumerState<CategoryRulesPage> createState() => _CategoryRulesPageState();
}

class _CategoryRulesPageState extends ConsumerState<CategoryRulesPage> {
  bool _running = false;
  double? _progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rules = ref.watch(categoryRulesProvider);
    final names = ref.watch(categoryNameMapProvider).value ?? const <int, String>{};

    return Scaffold(
      appBar: AppBar(
        title: const Text('分类规则'),
        actions: <Widget>[
          IconButton(
            tooltip: '新增规则',
            onPressed: _running ? null : () => _openEditor(null),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: rules.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stack) =>
            EmptyState(title: '读取规则失败', description: '$error'),
        data: (List<CategoryRule> all) {
          final custom = all.where((rule) => !rule.isBuiltin).toList();
          final builtin = all.where((rule) => rule.isBuiltin).toList();

          return ListView(
            padding: const EdgeInsets.fromLTRB(
              AppDimens.pagePadding,
              AppDimens.gapS,
              AppDimens.pagePadding,
              AppDimens.gapXl,
            ),
            children: <Widget>[
              _RecategorizeCard(
                running: _running,
                progress: _progress,
                onRun: _recategorize,
              ),
              const SizedBox(height: AppDimens.gapL),
              if (custom.isNotEmpty) ...<Widget>[
                SectionHeader('自定义规则（${custom.length}）'),
                for (final rule in custom) ...<Widget>[
                  _RuleTile(
                    rule: rule,
                    targetLabel: _labelOf(rule, names),
                    onToggle: (value) => _toggle(rule, value),
                    onTap: () => _openEditor(rule),
                    onDelete: () => _delete(rule),
                  ),
                  const SizedBox(height: AppDimens.gapM),
                ],
                const SizedBox(height: AppDimens.gapS),
              ],
              SectionHeader('内置规则（${builtin.length}）'),
              Padding(
                padding: const EdgeInsets.only(
                  left: AppDimens.gapXs,
                  bottom: AppDimens.gapM,
                ),
                child: Text(
                  '内置规则可以修改和禁用，但不能删除 —— 删掉就找不回来了。',
                  style: theme.textTheme.labelSmall,
                ),
              ),
              for (final rule in builtin) ...<Widget>[
                _RuleTile(
                  rule: rule,
                  targetLabel: _labelOf(rule, names),
                  onToggle: (value) => _toggle(rule, value),
                  onTap: () => _openEditor(rule),
                  onDelete: null,
                ),
                const SizedBox(height: AppDimens.gapM),
              ],
            ],
          );
        },
      ),
    );
  }

  String _labelOf(CategoryRule rule, Map<int, String> names) {
    final top = names[rule.targetCategoryId] ?? '未知分类';
    final sub = rule.targetSubcategoryId == null
        ? null
        : names[rule.targetSubcategoryId!];
    return sub == null || sub.isEmpty ? top : '$top / $sub';
  }

  Future<void> _toggle(CategoryRule rule, bool enabled) async {
    final id = rule.id;
    if (id == null) {
      return;
    }
    await ref.read(ruleRepositoryProvider).setRuleEnabled(id, enabled);
    _invalidateRules();
  }

  Future<void> _delete(CategoryRule rule) async {
    final id = rule.id;
    if (id == null || rule.isBuiltin) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除规则'),
        content: Text('确定删除「${rule.name}」吗？已经分类好的账单不会变，'
            '但之后的新账单不会再命中这条规则。'),
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
    await ref.read(ruleRepositoryProvider).deleteRule(id);
    _invalidateRules();
  }

  Future<void> _openEditor(CategoryRule? existing) async {
    final result = await showModalBottomSheet<_RuleDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _RuleEditorSheet(existing: existing),
    );
    if (result == null) {
      return;
    }

    final repository = ref.read(ruleRepositoryProvider);
    if (existing?.id == null) {
      await repository.createRule(result.toRule());
    } else {
      await repository.updateRule(
        result.toRule(id: existing!.id, isBuiltin: existing.isBuiltin),
      );
    }
    _invalidateRules();
  }

  Future<void> _recategorize() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('重新分类历史账单'),
        content: const Text(
          '将用当前规则重新判断所有账单的分类。\n\n'
          '· 你**手动指定过分类**的账单会被完整保留，不会被覆盖\n'
          '· 只有分类结果发生变化的账单才会被写入\n'
          '· 全程在本机完成，不联网',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('开始'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }

    setState(() {
      _running = true;
      _progress = null;
    });

    final messenger = ScaffoldMessenger.of(context);
    try {
      final service =
          await ref.read(recategorizationServiceProvider.future);
      final result = await service.run(
        onProgress: (int done, int total) {
          if (!mounted || total == 0) {
            return;
          }
          setState(() => _progress = done / total);
        },
      );

      if (!mounted) {
        return;
      }
      _invalidateRules();
      _invalidateData();
      setState(() {
        _running = false;
        _progress = null;
      });

      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '重跑完成：共 ${result.totalTransactions} 条，'
            '改写 ${result.changed} 条，'
            '保留手动分类 ${result.skippedManual} 条，'
            '仍未分类 ${result.stillUncategorized} 条'
            '（${result.elapsed.inMilliseconds}ms）',
          ),
          duration: const Duration(seconds: 6),
        ),
      );
    } on Exception catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _running = false;
        _progress = null;
      });
      messenger.showSnackBar(SnackBar(content: Text('重跑失败：$error')));
    }
  }

  void _invalidateRules() {
    ref
      ..invalidate(categoryRulesProvider)
      ..invalidate(merchantRulesProvider)
      // 规则变了 → 引擎必须重建
      ..invalidate(categorizationEngineProvider);
  }

  void _invalidateData() {
    ref
      ..invalidate(categoryTotalsProvider)
      ..invalidate(monthSummaryProvider)
      ..invalidate(previousMonthSummaryProvider)
      ..invalidate(monthlyTrendProvider)
      ..invalidate(merchantTotalsProvider)
      ..invalidate(dailyTotalsProvider)
      ..invalidate(timeBucketTotalsProvider)
      ..invalidate(topExpensesProvider)
      ..invalidate(recentTransactionsProvider)
      ..invalidate(budgetProgressProvider);
  }
}

/// 顶部的「重新分类」卡片。
class _RecategorizeCard extends StatelessWidget {
  const _RecategorizeCard({
    required this.running,
    required this.progress,
    required this.onRun,
  });

  final bool running;
  final double? progress;
  final VoidCallback onRun;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.auto_fix_high_outlined,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: AppDimens.gapS),
              Text('重新分类历史账单', style: theme.textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: AppDimens.gapS),
          Text(
            '改完规则后点一下，让历史账单按新规则重算。'
            '手动改过分类的账单不会被覆盖。',
            style: theme.textTheme.labelSmall,
          ),
          const SizedBox(height: AppDimens.gapM),
          if (running) ...<Widget>[
            LinearProgressIndicator(
              value: progress,
              minHeight: 4,
            ),
            const SizedBox(height: AppDimens.gapS),
            Text(
              progress == null
                  ? '准备中…'
                  : '${(progress! * 100).toStringAsFixed(0)}%',
              style: theme.textTheme.labelSmall,
            ),
          ] else
            FilledButton.tonalIcon(
              onPressed: onRun,
              icon: const Icon(Icons.play_arrow_outlined, size: 18),
              label: const Text('开始重新分类'),
            ),
        ],
      ),
    );
  }
}

class _RuleTile extends StatelessWidget {
  const _RuleTile({
    required this.rule,
    required this.targetLabel,
    required this.onToggle,
    required this.onTap,
    required this.onDelete,
  });

  final CategoryRule rule;
  final String targetLabel;
  final ValueChanged<bool> onToggle;
  final VoidCallback onTap;

  /// 内置规则传 `null`（不可删除）。
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final keywords = <String>[
      ...rule.merchantContains,
      ...rule.descriptionContains,
    ];

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(
        AppDimens.gapM,
        AppDimens.gapS,
        AppDimens.gapS,
        AppDimens.gapM,
      ),
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
                      rule.name,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: rule.enabled
                            ? theme.colorScheme.onSurface
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '→ $targetLabel · 优先级 ${rule.priority}'
                      '${rule.hitCount > 0 ? ' · 命中 ${rule.hitCount} 次' : ''}',
                      style: theme.textTheme.labelSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Switch(
                value: rule.enabled,
                onChanged: onToggle,
              ),
              if (onDelete != null)
                IconButton(
                  tooltip: '删除',
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          if (keywords.isNotEmpty) ...<Widget>[
            const SizedBox(height: AppDimens.gapS),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: <Widget>[
                for (final keyword in keywords.take(8))
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      keyword,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                if (keywords.length > 8)
                  Text(
                    '+${keywords.length - 8}',
                    style: theme.textTheme.labelSmall,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// 规则编辑结果。
class _RuleDraft {
  const _RuleDraft({
    required this.name,
    required this.priority,
    required this.merchantKeywords,
    required this.descriptionKeywords,
    required this.matchMode,
    required this.categoryId,
    required this.subcategoryId,
  });

  final String name;
  final int priority;
  final List<String> merchantKeywords;
  final List<String> descriptionKeywords;
  final RuleMatchMode matchMode;
  final int categoryId;
  final int? subcategoryId;

  CategoryRule toRule({int? id, bool isBuiltin = false}) => CategoryRule(
        id: id,
        name: name,
        priority: priority,
        merchantContains: merchantKeywords,
        descriptionContains: descriptionKeywords,
        matchMode: matchMode,
        targetCategoryId: categoryId,
        targetSubcategoryId: subcategoryId,
        isBuiltin: isBuiltin,
      );
}

/// 规则编辑弹层。
class _RuleEditorSheet extends ConsumerStatefulWidget {
  const _RuleEditorSheet({this.existing});

  final CategoryRule? existing;

  @override
  ConsumerState<_RuleEditorSheet> createState() => _RuleEditorSheetState();
}

class _RuleEditorSheetState extends ConsumerState<_RuleEditorSheet> {
  late final TextEditingController _nameController;
  late final TextEditingController _priorityController;
  late final TextEditingController _merchantController;
  late final TextEditingController _descriptionController;
  late RuleMatchMode _matchMode;
  int? _categoryId;
  int? _subcategoryId;
  String? _error;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameController = TextEditingController(text: existing?.name ?? '');
    _priorityController = TextEditingController(
      text: '${existing?.priority ?? 50}',
    );
    _merchantController = TextEditingController(
      text: existing?.merchantContains.join('，') ?? '',
    );
    _descriptionController = TextEditingController(
      text: existing?.descriptionContains.join('，') ?? '',
    );
    _matchMode = existing?.matchMode ?? RuleMatchMode.any;
    _categoryId = existing?.targetCategoryId;
    _subcategoryId = existing?.targetSubcategoryId;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priorityController.dispose();
    _merchantController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categories = ref.watch(allCategoriesProvider).value ?? const <Category>[];
    final topLevel =
        categories.where((item) => item.isTopLevel).toList(growable: false);
    final children = categories
        .where((item) => item.parentId == _categoryId)
        .toList(growable: false);

    return Padding(
      padding: EdgeInsets.only(
        left: AppDimens.pagePadding,
        right: AppDimens.pagePadding,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppDimens.gapXl,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              widget.existing == null ? '新增规则' : '编辑规则',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: AppDimens.gapL),

            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: '规则名称'),
            ),
            const SizedBox(height: AppDimens.gapM),
            TextField(
              controller: _priorityController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: '优先级',
                helperText: '数字越小越先匹配',
              ),
            ),
            const SizedBox(height: AppDimens.gapM),
            TextField(
              controller: _merchantController,
              decoration: const InputDecoration(
                labelText: '商户包含关键词',
                hintText: '用逗号分隔，例如：瑞幸，星巴克，喜茶',
              ),
            ),
            const SizedBox(height: AppDimens.gapM),
            TextField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: '商品/描述包含关键词（可选）',
                hintText: '用逗号分隔，例如：外卖，会员',
              ),
            ),
            const SizedBox(height: AppDimens.gapL),

            Text('匹配模式', style: theme.textTheme.labelSmall),
            const SizedBox(height: AppDimens.gapS),
            SegmentedButton<RuleMatchMode>(
              segments: <ButtonSegment<RuleMatchMode>>[
                for (final mode in RuleMatchMode.values)
                  ButtonSegment<RuleMatchMode>(
                    value: mode,
                    label: Text(mode.label),
                  ),
              ],
              selected: <RuleMatchMode>{_matchMode},
              onSelectionChanged: (selection) =>
                  setState(() => _matchMode = selection.first),
            ),
            const SizedBox(height: AppDimens.gapL),

            Text('目标分类', style: theme.textTheme.labelSmall),
            const SizedBox(height: AppDimens.gapS),
            Wrap(
              spacing: AppDimens.gapS,
              runSpacing: AppDimens.gapS,
              children: <Widget>[
                for (final category in topLevel)
                  ChoiceChip(
                    label: Text(category.name),
                    selected: _categoryId == category.id,
                    onSelected: (_) => setState(() {
                      _categoryId = category.id;
                      _subcategoryId = null;
                    }),
                  ),
              ],
            ),
            if (children.isNotEmpty) ...<Widget>[
              const SizedBox(height: AppDimens.gapM),
              Text('二级分类（可选）', style: theme.textTheme.labelSmall),
              const SizedBox(height: AppDimens.gapS),
              Wrap(
                spacing: AppDimens.gapS,
                runSpacing: AppDimens.gapS,
                children: <Widget>[
                  for (final child in children)
                    ChoiceChip(
                      label: Text(child.name),
                      selected: _subcategoryId == child.id,
                      onSelected: (_) => setState(() {
                        _subcategoryId =
                            _subcategoryId == child.id ? null : child.id;
                      }),
                    ),
                ],
              ),
            ],
            if (_error != null) ...<Widget>[
              const SizedBox(height: AppDimens.gapM),
              Text(
                _error!,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ],

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
      ),
    );
  }

  void _submit() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = '请填写规则名称');
      return;
    }
    final priority = int.tryParse(_priorityController.text.trim()) ?? 50;
    final merchant = _splitKeywords(_merchantController.text);
    final description = _splitKeywords(_descriptionController.text);

    if (merchant.isEmpty && description.isEmpty) {
      setState(() => _error = '至少要填一个关键词，否则规则会命中所有账单');
      return;
    }
    if (_matchMode == RuleMatchMode.merchantAndDescription &&
        (merchant.isEmpty || description.isEmpty)) {
      setState(() => _error = '「商户且描述」模式需要两边都填关键词');
      return;
    }
    if (_categoryId == null) {
      setState(() => _error = '请选择目标分类');
      return;
    }

    Navigator.of(context).pop(
      _RuleDraft(
        name: name,
        priority: priority,
        merchantKeywords: merchant,
        descriptionKeywords: description,
        matchMode: _matchMode,
        categoryId: _categoryId!,
        subcategoryId: _subcategoryId,
      ),
    );
  }

  /// 中英文逗号、分号、竖线都当分隔符。
  List<String> _splitKeywords(String raw) => raw
      .split(RegExp(r'[,，;；|\n]'))
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}
