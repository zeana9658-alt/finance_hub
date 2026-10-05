import 'package:finance_hub/app/providers.dart';
import 'package:finance_hub/app/theme/app_colors.dart';
import 'package:finance_hub/core/errors/app_error.dart';
import 'package:finance_hub/core/money/money.dart';
import 'package:finance_hub/domain/entities/category.dart';
import 'package:finance_hub/domain/entities/normalized_transaction.dart';
import 'package:finance_hub/domain/enums/bill_source.dart';
import 'package:finance_hub/domain/enums/transaction_type.dart';
import 'package:finance_hub/domain/services/categorization_engine.dart';
import 'package:finance_hub/domain/services/manual_entry.dart';
import 'package:finance_hub/features/import/import_entry.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 快速记账 —— brief 第 27 条。
///
/// 打开方式：首页 / 账单页的「＋」。
///
/// 一个设计上的小用心：输入商户名时会用**和导入同一套分类引擎**实时给出
/// 分类建议（商户记忆 → 平台分类 → 关键词规则），点一下就应用。
/// 这样用户手记几笔之后，常用商户的分类会越来越省事。
class QuickEntrySheet extends ConsumerStatefulWidget {
  const QuickEntrySheet({super.key});

  /// 以底部弹层形式打开。
  static Future<void> open(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const QuickEntrySheet(),
    );
  }

  @override
  ConsumerState<QuickEntrySheet> createState() => _QuickEntrySheetState();
}

class _QuickEntrySheetState extends ConsumerState<QuickEntrySheet> {
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _merchantController = TextEditingController();
  final TextEditingController _paymentController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();

  TransactionType _type = TransactionType.expense;
  DateTime _occurredAt = DateTime.now();
  int? _categoryId;
  int? _subcategoryId;
  String? _error;
  bool _saving = false;

  /// 引擎给出的分类建议（用户点「应用」才真正生效）。
  CategoryAssignment? _suggestion;

  @override
  void dispose() {
    _amountController.dispose();
    _merchantController.dispose();
    _paymentController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categories = ref.watch(allCategoriesProvider).value ?? const <Category>[];
    final names = ref.watch(categoryNameMapProvider).value ?? const <int, String>{};

    final wantedKind = _type == TransactionType.income
        ? CategoryKind.income
        : CategoryKind.expense;
    final topLevel = categories
        .where((item) => item.isTopLevel && item.kind == wantedKind)
        .toList(growable: false);
    final children = categories
        .where((item) => item.parentId == _categoryId)
        .toList(growable: false);

    return Padding(
      padding: EdgeInsets.only(
        left: AppDimens.pagePadding,
        right: AppDimens.pagePadding,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppDimens.gapL,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('记一笔', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppDimens.gapL),

            // ── 收入 / 支出 ──
            SegmentedButton<TransactionType>(
              segments: const <ButtonSegment<TransactionType>>[
                ButtonSegment<TransactionType>(
                  value: TransactionType.expense,
                  label: Text('支出'),
                ),
                ButtonSegment<TransactionType>(
                  value: TransactionType.income,
                  label: Text('收入'),
                ),
              ],
              selected: <TransactionType>{_type},
              onSelectionChanged: (selection) => setState(() {
                _type = selection.first;
                // 收支切换后原来的分类可能不属于新方向，清掉避免错配
                _categoryId = null;
                _subcategoryId = null;
                _suggestion = null;
              }),
            ),
            const SizedBox(height: AppDimens.gapL),

            // ── 金额 ──
            TextField(
              controller: _amountController,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              style: theme.textTheme.displaySmall,
              decoration: InputDecoration(
                prefixText: '\u00A5 ',
                hintText: '0.00',
                errorText: _error,
              ),
            ),
            const SizedBox(height: AppDimens.gapL),

            // ── 分类 ──
            Text('分类', style: theme.textTheme.labelSmall),
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

            // ── 分类建议 ──
            if (_suggestion != null && _suggestion!.isAssigned) ...<Widget>[
              const SizedBox(height: AppDimens.gapM),
              _SuggestionBar(
                label: _labelOf(_suggestion!.categoryId, _suggestion!.subcategoryId, names),
                reason: _suggestion!.source.label,
                onApply: () => setState(() {
                  _categoryId = _suggestion!.categoryId;
                  _subcategoryId = _suggestion!.subcategoryId;
                  _suggestion = null;
                }),
              ),
            ],

            const SizedBox(height: AppDimens.gapL),

            // ── 商户 ──
            TextField(
              controller: _merchantController,
              decoration: const InputDecoration(
                labelText: '商户（可选）',
                hintText: '例如：星巴克',
              ),
              onChanged: (_) => _refreshSuggestion(),
            ),
            const SizedBox(height: AppDimens.gapM),

            // ── 日期 ──
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.event_outlined, size: 18),
                    label: Text(_formatDate(_occurredAt)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppDimens.gapM),

            // ── 支付方式 / 备注 ──
            TextField(
              controller: _paymentController,
              decoration: const InputDecoration(
                labelText: '支付方式（可选）',
                hintText: '例如：微信零钱、支付宝余额',
              ),
            ),
            const SizedBox(height: AppDimens.gapM),
            TextField(
              controller: _noteController,
              decoration: const InputDecoration(labelText: '备注（可选）'),
            ),

            const SizedBox(height: AppDimens.gapXl),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving ? null : () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: AppDimens.gapM),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('保存'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppDimens.gapS),
            Center(
              child: TextButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  ImportEntry.open(context, ref);
                },
                icon: const Icon(Icons.file_download_outlined, size: 16),
                label: const Text('改从账单文件导入'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ───────────────────────── 分类建议 ─────────────────────────

  /// 用与导入**同一套引擎**给出建议。
  ///
  /// 只在用户还没选分类、且商户名非空时才提示，避免打扰。
  Future<void> _refreshSuggestion() async {
    final merchant = _merchantController.text.trim();
    if (merchant.isEmpty || _categoryId != null) {
      if (_suggestion != null) {
        setState(() => _suggestion = null);
      }
      return;
    }

    final engine = await ref.read(categorizationEngineProvider.future);
    if (!mounted) {
      return;
    }

    final draft = NormalizedTransaction(
      source: BillSource.manual,
      uniqueKey: 'suggestion',
      transactionTime: _occurredAt,
      transactionTimeRaw: '',
      transactionType: _type,
      transactionTypeRaw: '',
      amountCents: 100,
      merchant: merchant,
      description: '',
      paymentMethod: _paymentController.text.trim(),
      createdAt: _occurredAt,
      updatedAt: _occurredAt,
    );
    final assignment = engine.categorize(draft);
    setState(() => _suggestion = assignment.isAssigned ? assignment : null);
  }

  String _labelOf(int? categoryId, int? subcategoryId, Map<int, String> names) {
    final top = categoryId == null ? null : names[categoryId];
    if (top == null || top.isEmpty) {
      return '';
    }
    final sub = subcategoryId == null ? null : names[subcategoryId];
    return sub == null || sub.isEmpty ? top : '$top / $sub';
  }

  // ───────────────────────── 日期 ─────────────────────────

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _occurredAt,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      helpText: '选择日期',
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      // 保留原来的时分秒，只换日期
      _occurredAt = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _occurredAt.hour,
        _occurredAt.minute,
        _occurredAt.second,
      );
    });
  }

  // ───────────────────────── 保存 ─────────────────────────

  Future<void> _save() async {
    final cents = parseMoneyToCents(_amountController.text);
    if (cents == null || cents <= 0) {
      setState(() => _error = '请输入大于 0 的金额');
      return;
    }
    if (_categoryId == null) {
      setState(() => _error = '请选择分类');
      return;
    }

    setState(() {
      _error = null;
      _saving = true;
    });

    final messenger = ScaffoldMessenger.of(context);
    try {
      final transaction = ManualEntry.build(
        type: _type,
        amountCents: cents,
        occurredAt: _occurredAt,
        categoryId: _categoryId,
        subcategoryId: _subcategoryId,
        merchant: _merchantController.text,
        note: _noteController.text,
        paymentMethod: _paymentController.text,
      );

      final inserted = await ref
          .read(transactionRepositoryProvider)
          .insertAll(<NormalizedTransaction>[transaction]);

      if (!mounted) {
        return;
      }
      _invalidateAll();
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            inserted > 0
                ? '已记一笔：${_type.label} '
                    '${formatCents(cents, withSymbol: true)}'
                : '这笔没有写入（可能重复）',
          ),
        ),
      );
    } on AppException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _error = error.toString();
      });
    } on Exception catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _error = '保存失败：$error';
      });
    }
  }

  void _invalidateAll() {
    ref
      ..invalidate(transactionCountProvider)
      ..invalidate(monthSummaryProvider)
      ..invalidate(previousMonthSummaryProvider)
      ..invalidate(categoryTotalsProvider)
      ..invalidate(topExpensesProvider)
      ..invalidate(dailyTotalsProvider)
      ..invalidate(timeBucketTotalsProvider)
      ..invalidate(monthlyTrendProvider)
      ..invalidate(merchantTotalsProvider)
      ..invalidate(budgetProgressProvider)
      ..invalidate(recentTransactionsProvider)
      ..invalidate(earliestTransactionProvider);
  }

  String _formatDate(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)}';
  }
}

/// 分类建议提示条。
class _SuggestionBar extends StatelessWidget {
  const _SuggestionBar({
    required this.label,
    required this.reason,
    required this.onApply,
  });

  final String label;
  final String reason;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.gapM,
        vertical: AppDimens.gapS,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppDimens.radiusSmall),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.lightbulb_outline,
            size: 16,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: AppDimens.gapS),
          Expanded(
            child: Text(
              '建议：$label（$reason）',
              style: theme.textTheme.labelSmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            onPressed: onApply,
            child: const Text('应用'),
          ),
        ],
      ),
    );
  }
}
