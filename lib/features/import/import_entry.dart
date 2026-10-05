import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:finance_hub/app/providers.dart';
import 'package:finance_hub/app/theme/app_colors.dart';
import 'package:finance_hub/core/errors/app_error.dart';
import 'package:finance_hub/core/money/money.dart';
import 'package:finance_hub/domain/entities/category.dart';
import 'package:finance_hub/domain/enums/bill_source.dart';
import 'package:finance_hub/domain/enums/category_source.dart';
import 'package:finance_hub/domain/enums/transaction_type.dart';
import 'package:finance_hub/import/detect/source_detector.dart';
import 'package:finance_hub/import/models/import_candidate.dart';
import 'package:finance_hub/import/models/import_preview.dart';
import 'package:finance_hub/shared/widgets/amount_text.dart';
import 'package:finance_hub/shared/widgets/app_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 导入入口。
///
/// 流程（docs/ARCHITECTURE.md §3.1）：
/// ```
/// 选择文件 / 粘贴文本 → 解析 → 预览 → 用户确认 → 写库
/// ```
/// **预览阶段不写任何数据**，用户取消时零副作用。
class ImportEntry {
  ImportEntry._();

  /// 打开导入入口（底部弹层）。
  static Future<void> open(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.insert_drive_file_outlined),
              title: const Text('选择账单文件'),
              subtitle: const Text('支持 CSV / XLSX（微信、支付宝）'),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                await _pickFile(context, ref);
              },
            ),
            ListTile(
              leading: const Icon(Icons.content_paste_outlined),
              title: const Text('粘贴表格文本'),
              subtitle: const Text('从账单页面复制的内容直接粘贴'),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                await _pasteText(context, ref);
              },
            ),
            const SizedBox(height: AppDimens.gapS),
          ],
        ),
      ),
    );
  }

  /// 统一构建预览 —— 一次性拿到「分类引擎 + 分类名映射」。
  static Future<ImportPreview> _buildPreview(
    WidgetRef ref, {
    Uint8List? bytes,
    String? path,
    String? text,
    BillSource? forcedSource,
  }) async {
    final pipeline = await ref.read(importPipelineProvider.future);
    final categoryNames = await ref.read(categoryNameMapProvider.future);

    if (text != null) {
      return pipeline.previewText(
        text,
        forcedSource: forcedSource,
        categoryNames: categoryNames,
      );
    }
    return pipeline.previewFile(
      path: path ?? '',
      bytes: bytes ?? Uint8List(0),
      forcedSource: forcedSource,
      categoryNames: categoryNames,
    );
  }

  static Future<void> _pickFile(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);

    List<PlatformFile> picked;
    try {
      picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: <String>['csv', 'xlsx', 'xls', 'txt'],
      );
    } on Exception catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('打开文件选择器失败：$error')),
      );
      return;
    }

    if (picked.isEmpty) {
      return;
    }

    final file = picked.first;
    final Uint8List bytes;
    try {
      bytes = await file.xFile.readAsBytes();
    } on Exception catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('无法读取文件内容：$error')));
      return;
    }

    if (!context.mounted) {
      return;
    }

    try {
      final preview = await _buildPreview(ref, path: file.name, bytes: bytes);
      if (!context.mounted) {
        return;
      }
      await _openPreviewPage(context, ref, preview);
    } on AppException catch (error) {
      if (!context.mounted) {
        return;
      }
      await _handlePipelineError(
        context,
        ref,
        error,
        bytes: bytes,
        path: file.name,
      );
    }
  }

  static Future<void> _pasteText(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('粘贴表格文本'),
        content: SizedBox(
          width: 480,
          child: TextField(
            controller: controller,
            maxLines: 10,
            decoration: const InputDecoration(
              hintText: '把账单页面复制的内容粘贴到这里（Tab 或逗号分隔）',
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('解析'),
          ),
        ],
      ),
    );

    if (text == null || text.trim().isEmpty || !context.mounted) {
      return;
    }

    try {
      final preview = await _buildPreview(ref, text: text);
      if (!context.mounted) {
        return;
      }
      await _openPreviewPage(context, ref, preview);
    } on AppException catch (error) {
      if (!context.mounted) {
        return;
      }
      await _handlePipelineError(context, ref, error, text: text);
    }
  }

  /// 来源无法自动识别时，让用户手动选择后重试。
  static Future<void> _handlePipelineError(
    BuildContext context,
    WidgetRef ref,
    AppException error, {
    Uint8List? bytes,
    String? path,
    String? text,
  }) async {
    if (error is! SourceNotDeterminedException) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('无法解析：$error')),
      );
      return;
    }

    final source = await _askSource(context);
    if (source == null || !context.mounted) {
      return;
    }

    try {
      final preview = await _buildPreview(
        ref,
        bytes: bytes,
        path: path,
        text: text,
        forcedSource: source,
      );
      if (!context.mounted) {
        return;
      }
      await _openPreviewPage(context, ref, preview);
    } on AppException catch (retryError) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('仍然无法解析：$retryError')),
      );
    }
  }

  static Future<BillSource?> _askSource(BuildContext context) {
    return showDialog<BillSource>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('无法自动识别账单来源'),
        content: const Text('未能从表头或文件名判断这是哪个平台的账单，请手动选择：'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(BillSource.wechat),
            child: const Text('微信支付'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(BillSource.alipay),
            child: const Text('支付宝'),
          ),
        ],
      ),
    );
  }

  static Future<void> _openPreviewPage(
    BuildContext context,
    WidgetRef ref,
    ImportPreview preview,
  ) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => _ImportPreviewPage(initialPreview: preview),
      ),
    );
  }
}

/// 导入预览页 —— brief 第 7 条 + 第 10/11 条（可改分类、记住商户）。
class _ImportPreviewPage extends ConsumerStatefulWidget {
  const _ImportPreviewPage({required this.initialPreview});

  final ImportPreview initialPreview;

  @override
  ConsumerState<_ImportPreviewPage> createState() => _ImportPreviewPageState();
}

class _ImportPreviewPageState extends ConsumerState<_ImportPreviewPage> {
  late ImportPreview _preview;
  CandidateStatus? _filter;
  bool _importing = false;

  /// 待写入的商户记忆：`merchantKey → (展示名, 分类, 二级分类)`。
  ///
  /// 用户在预览里改过分类的商户会被记下来，确认导入时一并写入
  /// `merchant_rules` —— 这就是 brief 第 11 条「系统记住商户分类」。
  final Map<String, _PendingMerchantMemory> _pendingMemories =
      <String, _PendingMerchantMemory>{};

  @override
  void initState() {
    super.initState();
    _preview = widget.initialPreview;
  }

  Future<void> _confirm() async {
    final selected = _preview.selectedCandidates;
    if (selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有勾选任何可导入的交易')),
      );
      return;
    }

    setState(() => _importing = true);
    final repository = ref.read(transactionRepositoryProvider);
    final ruleRepository = ref.read(ruleRepositoryProvider);
    final transactions = selected
        .map((candidate) => candidate.transaction!)
        .toList(growable: false);

    try {
      final inserted = await repository.insertAll(transactions);

      // 写入商户记忆（只写用户在预览里明确改过分类的商户）
      for (final memory in _pendingMemories.values) {
        await ruleRepository.rememberMerchant(
          merchant: memory.merchantDisplay,
          categoryId: memory.categoryId,
          subcategoryId: memory.subcategoryId,
        );
      }

      if (!mounted) {
        return;
      }
      _invalidateAll();
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '导入完成：新增 $inserted 条'
            '${inserted < transactions.length ? '（${transactions.length - inserted} 条被去重拦下）' : ''}'
            '${_pendingMemories.isEmpty ? '' : '，记住 ${_pendingMemories.length} 个商户分类'}',
          ),
        ),
      );
    } on Exception catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _importing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('写入失败：$error')),
      );
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
      ..invalidate(earliestTransactionProvider)
      // 规则/商户记忆变了 → 引擎要重建
      ..invalidate(categorizationEngineProvider);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _preview.filterBy(_filter);
    final categories = ref.watch(allCategoriesProvider);
    final names = ref.watch(categoryNameMapProvider).value ?? const <int, String>{};

    return Scaffold(
      appBar: AppBar(
        title: Text(_preview.label, overflow: TextOverflow.ellipsis),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(20),
          child: Padding(
            padding: const EdgeInsets.only(
              left: AppDimens.pagePadding,
              right: AppDimens.pagePadding,
              bottom: AppDimens.gapS,
            ),
            child: Row(
              children: <Widget>[
                Text(
                  '发现 ${_preview.totalCount} 条交易',
                  style: theme.textTheme.bodySmall,
                ),
                const Spacer(),
                Flexible(
                  child: Text(
                    '来源：${_preview.source.label}'
                    '（${_basisLabel(_preview.detectionBasis)}）',
                    style: theme.textTheme.labelSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(AppDimens.pagePadding),
            child: _StatsPanel(preview: _preview),
          ),
          _FilterBar(
            preview: _preview,
            selected: _filter,
            onChanged: (value) => setState(() => _filter = value),
          ),
          const SizedBox(height: AppDimens.gapS),
          Expanded(
            child: filtered.isEmpty
                ? const EmptyState(title: '该分类下没有记录')
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(
                      AppDimens.pagePadding,
                      0,
                      AppDimens.pagePadding,
                      AppDimens.pagePadding,
                    ),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppDimens.gapS),
                    itemBuilder: (context, index) => _CandidateTile(
                      candidate: filtered[index],
                      categoryNames: names,
                      onToggle: _toggle,
                      onEditCategory: () => _editCategory(
                        filtered[index],
                        categories.value ?? const <Category>[],
                        names,
                      ),
                    ),
                  ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppDimens.pagePadding),
          child: Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton(
                  onPressed:
                      _importing ? null : () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
              ),
              const SizedBox(width: AppDimens.gapM),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: _importing ? null : _confirm,
                  child: _importing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text('确认导入 ${_preview.selectedCount} 条'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _toggle(ImportCandidate candidate) {
    final updated = List<ImportCandidate>.of(_preview.candidates);
    updated[candidate.index] = candidate.copyWith(
      isSelected: !candidate.isSelected,
    );
    setState(() => _preview = _preview.copyWith(candidates: updated));
  }

  Future<void> _editCategory(
    ImportCandidate candidate,
    List<Category> categories,
    Map<int, String> names,
  ) async {
    final transaction = candidate.transaction;
    if (transaction == null) {
      return;
    }

    final pick = await showModalBottomSheet<_CategoryPick>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CategoryPickerSheet(
        categories: categories,
        initialCategoryId: transaction.categoryId,
        initialSubcategoryId: transaction.subcategoryId,
      ),
    );
    if (pick == null || !mounted) {
      return;
    }

    // 更新候选：分类改为「手动指定」，从而在后续重新分类时被保护
    final updated = List<ImportCandidate>.of(_preview.candidates);
    final updatedTransaction = transaction.copyWith(
      categoryId: pick.categoryId,
      subcategoryId: pick.subcategoryId,
      categorySource: CategorySource.manual,
    );
    updated[candidate.index] = candidate.copyWith(
      transaction: updatedTransaction,
      categoryLabel: _labelOf(pick.categoryId, pick.subcategoryId, names),
    );
    setState(() => _preview = _preview.copyWith(candidates: updated));

    // 记住这个商户（导入确认时落库）
    if (pick.categoryId != null && transaction.merchant.trim().isNotEmpty) {
      _pendingMemories[transaction.merchant.trim().toLowerCase()] =
          _PendingMerchantMemory(
        merchantDisplay: transaction.merchant.trim(),
        categoryId: pick.categoryId!,
        subcategoryId: pick.subcategoryId,
      );
    }
  }

  String _labelOf(int? categoryId, int? subcategoryId, Map<int, String> names) {
    final top = categoryId == null ? null : names[categoryId];
    if (top == null || top.isEmpty) {
      return '';
    }
    final sub = subcategoryId == null ? null : names[subcategoryId];
    return sub == null || sub.isEmpty ? top : '$top / $sub';
  }

  String _basisLabel(DetectionBasis basis) {
    switch (basis) {
      case DetectionBasis.header:
        return '表头识别';
      case DetectionBasis.filename:
        return '文件名识别';
      case DetectionBasis.manual:
        return '手动选择';
      case DetectionBasis.unknown:
        return '未知';
    }
  }
}

/// 待写入的商户记忆。
class _PendingMerchantMemory {
  const _PendingMerchantMemory({
    required this.merchantDisplay,
    required this.categoryId,
    this.subcategoryId,
  });

  final String merchantDisplay;
  final int categoryId;
  final int? subcategoryId;
}

/// 分类选择结果。
class _CategoryPick {
  const _CategoryPick({this.categoryId, this.subcategoryId});

  final int? categoryId;
  final int? subcategoryId;
}

/// 顶部统计面板：可导入 / 重复 / 异常 + 收入支出合计。
class _StatsPanel extends StatelessWidget {
  const _StatsPanel({required this.preview});

  final ImportPreview preview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      padding: const EdgeInsets.all(AppDimens.gapM),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: _StatCell(
                  icon: Icons.check_circle_outline,
                  label: '可导入',
                  value: '${preview.validCount}',
                  color: theme.colorScheme.primary,
                ),
              ),
              Expanded(
                child: _StatCell(
                  icon: Icons.refresh,
                  label: '重复',
                  value: '${preview.duplicateCount}',
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              Expanded(
                child: _StatCell(
                  icon: Icons.error_outline,
                  label: '数据异常',
                  value: '${preview.errorCount}',
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppDimens.gapM),
          const Divider(height: 1),
          const SizedBox(height: AppDimens.gapM),
          Row(
            children: <Widget>[
              Expanded(
                child: _SumCell(
                  label: '收入',
                  cents: preview.selectedIncomeCents,
                  type: TransactionType.income,
                ),
              ),
              Expanded(
                child: _SumCell(
                  label: '支出',
                  cents: preview.selectedExpenseCents,
                  type: TransactionType.expense,
                ),
              ),
            ],
          ),
          if (preview.suspectedCrossPlatformCount > 0) ...<Widget>[
            const SizedBox(height: AppDimens.gapM),
            Row(
              children: <Widget>[
                Icon(
                  Icons.info_outline,
                  size: 15,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '有 ${preview.suspectedCrossPlatformCount} 条与其他平台同日同额同商户，'
                    '已保留勾选，请自行确认是否重复',
                    style: theme.textTheme.labelSmall,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _SumCell extends StatelessWidget {
  const _SumCell({
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
    final isDark = theme.brightness == Brightness.dark;
    final color = type == TransactionType.income
        ? (isDark ? const Color(0xFF8FBFA0) : const Color(0xFF5B8C6E))
        : (isDark ? const Color(0xFFD99B7E) : const Color(0xFFC67B5C));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: theme.textTheme.labelSmall),
        const SizedBox(height: 2),
        Text(
          formatCents(cents, withSymbol: true),
          style: theme.textTheme.titleMedium?.copyWith(color: color),
        ),
      ],
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: <Widget>[
        Icon(icon, size: 20, color: color),
        const SizedBox(height: AppDimens.gapXs),
        Text(value, style: theme.textTheme.titleMedium),
        Text(label, style: theme.textTheme.labelSmall),
      ],
    );
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.preview,
    required this.selected,
    required this.onChanged,
  });

  final ImportPreview preview;
  final CandidateStatus? selected;
  final ValueChanged<CandidateStatus?> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: AppDimens.pagePadding),
      child: Row(
        children: <Widget>[
          ChoiceChip(
            label: Text('全部 ${preview.totalCount}'),
            selected: selected == null,
            onSelected: (_) => onChanged(null),
          ),
          const SizedBox(width: AppDimens.gapS),
          ChoiceChip(
            label: Text('可导入 ${preview.validCount}'),
            selected: selected == CandidateStatus.valid,
            onSelected: (_) => onChanged(CandidateStatus.valid),
          ),
          const SizedBox(width: AppDimens.gapS),
          ChoiceChip(
            label: Text('重复 ${preview.duplicateCount}'),
            selected: selected == CandidateStatus.duplicate,
            onSelected: (_) => onChanged(CandidateStatus.duplicate),
          ),
          const SizedBox(width: AppDimens.gapS),
          ChoiceChip(
            label: Text('异常 ${preview.errorCount}'),
            selected: selected == CandidateStatus.error,
            onSelected: (_) => onChanged(CandidateStatus.error),
          ),
        ],
      ),
    );
  }
}

class _CandidateTile extends StatelessWidget {
  const _CandidateTile({
    required this.candidate,
    required this.categoryNames,
    required this.onToggle,
    required this.onEditCategory,
  });

  final ImportCandidate candidate;
  final Map<int, String> categoryNames;
  final ValueChanged<ImportCandidate> onToggle;
  final VoidCallback onEditCategory;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tx = candidate.transaction;

    final Color statusColor;
    final IconData statusIcon;
    switch (candidate.status) {
      case CandidateStatus.valid:
        statusColor = theme.colorScheme.primary;
        statusIcon = Icons.check_circle_outline;
      case CandidateStatus.duplicate:
        statusColor = theme.colorScheme.onSurfaceVariant;
        statusIcon = Icons.refresh;
      case CandidateStatus.error:
        statusColor = theme.colorScheme.error;
        statusIcon = Icons.error_outline;
    }

    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppDimens.gapM,
        vertical: AppDimens.gapM,
      ),
      onTap: candidate.isSelectable ? () => onToggle(candidate) : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: candidate.isSelectable
                ? Checkbox(
                    value: candidate.isSelected,
                    onChanged: (_) => onToggle(candidate),
                    visualDensity: VisualDensity.compact,
                  )
                : Icon(statusIcon, size: 20, color: statusColor),
          ),
          const SizedBox(width: AppDimens.gapS),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        tx == null
                            ? '无法解析'
                            : (tx.merchant.isEmpty ? '未知商户' : tx.merchant),
                        style: theme.textTheme.bodyMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (tx != null)
                      AmountText(
                        cents: tx.amountCents,
                        type: tx.transactionType,
                        showSign: true,
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  candidate.status == CandidateStatus.error
                      ? '第 ${candidate.rowNumber} 行 · ${candidate.errorReason}'
                      : '第 ${candidate.rowNumber} 行 · ${candidate.rawSummary}',
                  style: theme.textTheme.labelSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (tx != null) ...<Widget>[
                  const SizedBox(height: AppDimens.gapXs),
                  Wrap(
                    spacing: AppDimens.gapS,
                    runSpacing: 4,
                    children: <Widget>[
                      _MiniTag(text: tx.source.label),
                      _MiniTag(
                        text: candidate.categoryLabel.isEmpty
                            ? '未分类'
                            : candidate.categoryLabel,
                        onTap: onEditCategory,
                        icon: Icons.edit_outlined,
                      ),
                      if (tx.categorySource == CategorySource.manual)
                        const _MiniTag(text: '手动指定'),
                      if (candidate.status == CandidateStatus.duplicate)
                        const _MiniTag(text: '重复', highlight: true),
                      if (candidate.isSuspectedCrossPlatform)
                        const _MiniTag(text: '疑似跨平台重复'),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniTag extends StatelessWidget {
  const _MiniTag({
    required this.text,
    this.highlight = false,
    this.onTap,
    this.icon,
  });

  final String text;
  final bool highlight;
  final VoidCallback? onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(
              icon,
              size: 12,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 3),
          ],
          Text(
            text,
            style: theme.textTheme.labelSmall?.copyWith(
              color: highlight
                  ? theme.colorScheme.error
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );

    if (onTap == null) {
      return content;
    }
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: content,
    );
  }
}

/// 分类选择弹层（一级 → 二级）。
class _CategoryPickerSheet extends StatefulWidget {
  const _CategoryPickerSheet({
    required this.categories,
    this.initialCategoryId,
    this.initialSubcategoryId,
  });

  final List<Category> categories;
  final int? initialCategoryId;
  final int? initialSubcategoryId;

  @override
  State<_CategoryPickerSheet> createState() => _CategoryPickerSheetState();
}

class _CategoryPickerSheetState extends State<_CategoryPickerSheet> {
  int? _categoryId;
  int? _subcategoryId;

  @override
  void initState() {
    super.initState();
    _categoryId = widget.initialCategoryId;
    _subcategoryId = widget.initialSubcategoryId;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final topLevel =
        widget.categories.where((item) => item.isTopLevel).toList(growable: false);
    final children = widget.categories
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
            Text('选择分类', style: theme.textTheme.titleMedium),
            const SizedBox(height: AppDimens.gapXs),
            Text(
              '选定后会记住这个商户，下次自动归类',
              style: theme.textTheme.labelSmall,
            ),
            const SizedBox(height: AppDimens.gapL),
            Text('一级分类', style: theme.textTheme.labelSmall),
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
              const SizedBox(height: AppDimens.gapL),
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
                    onPressed: _categoryId == null
                        ? null
                        : () => Navigator.of(context).pop(
                              _CategoryPick(
                                categoryId: _categoryId,
                                subcategoryId: _subcategoryId,
                              ),
                            ),
                    child: const Text('确定'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
