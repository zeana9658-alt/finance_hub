import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:finance_hub/app/providers.dart';
import 'package:finance_hub/app/theme/app_colors.dart';
import 'package:finance_hub/core/errors/app_error.dart';
import 'package:finance_hub/core/money/money.dart';
import 'package:finance_hub/domain/enums/bill_source.dart';
import 'package:finance_hub/domain/enums/transaction_type.dart';
import 'package:finance_hub/domain/services/import_pipeline.dart';
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

  static Future<void> _pickFile(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);

    FilePickerResult? picked;
    try {
      picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: <String>['csv', 'xlsx', 'xls', 'txt'],
        withData: true,
      );
    } on Exception catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('打开文件选择器失败：$error')),
      );
      return;
    }

    if (picked == null || picked.files.isEmpty) {
      return;
    }

    final file = picked.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('无法读取文件内容')),
      );
      return;
    }

    await _buildAndShowPreview(
      context,
      ref,
      bytes: bytes,
      path: file.name,
      origin: file.name,
      method: 'file',
      fileSize: file.size,
    );
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
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text),
            child: const Text('解析'),
          ),
        ],
      ),
    );

    if (text == null || text.trim().isEmpty) {
      return;
    }

    final pipeline = ref.read(importPipelineProvider);
    try {
      final preview = pipeline.previewText(text);
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

  static Future<void> _buildAndShowPreview(
    BuildContext context,
    WidgetRef ref, {
    required Uint8List bytes,
    required String path,
    required String origin,
    required String method,
    int? fileSize,
  }) async {
    final pipeline = ref.read(importPipelineProvider);
    try {
      final preview = pipeline.previewFile(path: path, bytes: bytes);
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
        path: path,
        origin: origin,
      );
    }
  }

  /// 来源无法自动识别时，让用户手动选择后重试。
  static Future<void> _handlePipelineError(
    BuildContext context,
    WidgetRef ref,
    AppException error, {
    Uint8List? bytes,
    String? path,
    String? origin,
    String? text,
  }) async {
    if (error is! SourceNotDeterminedException) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('无法解析：${error.toString()}')),
      );
      return;
    }

    final source = await _askSource(context);
    if (source == null || !context.mounted) {
      return;
    }

    final pipeline = ref.read(importPipelineProvider);
    try {
      final ImportPreview preview;
      if (text != null) {
        preview = pipeline.previewText(text, forcedSource: source);
      } else if (bytes != null && path != null) {
        preview = pipeline.previewFile(
          path: path,
          bytes: bytes,
          forcedSource: source,
        );
      } else {
        return;
      }
      if (!context.mounted) {
        return;
      }
      await _openPreviewPage(context, ref, preview);
    } on AppException catch (retryError) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('仍然无法解析：${retryError.toString()}')),
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
            onPressed: () =>
                Navigator.of(dialogContext).pop(BillSource.alipay),
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

/// 导入预览页 —— brief 第 7 条。
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
    final transactions = selected
        .map((candidate) => candidate.transaction!)
        .toList(growable: false);

    try {
      final inserted = await repository.insertAll(transactions);
      if (!mounted) {
        return;
      }
      ref.invalidate(transactionCountProvider);
      ref.invalidate(monthSummaryProvider);
      ref.invalidate(previousMonthSummaryProvider);
      ref.invalidate(categoryTotalsProvider);
      ref.invalidate(topExpensesProvider);
      ref.invalidate(dailyTotalsProvider);
      ref.invalidate(timeBucketTotalsProvider);
      ref.invalidate(recentTransactionsProvider);

      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '导入完成：新增 $inserted 条'
            '${inserted < transactions.length ? '（${transactions.length - inserted} 条被去重拦下）' : ''}',
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _preview.filterBy(_filter);

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
                Text(
                  '来源：${_preview.source.label}'
                  '（${_basisLabel(_preview.detectionBasis)}）',
                  style: theme.textTheme.labelSmall,
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
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppDimens.gapS),
                    itemBuilder: (context, index) => _CandidateTile(
                      candidate: filtered[index],
                      onToggle: _toggle,
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
                  onPressed: _importing
                      ? null
                      : () => Navigator.of(context).pop(),
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

/// 仅供 [_SumCell] 使用的类型别名，避免在此文件引入枚举。
typedef TransactionTypeShim = _TxType;

/// 与 `TransactionType` 取值一致的极简枚举，仅用于着色。
enum _TxType { income, expense }

class _SumCell extends StatelessWidget {
  const _SumCell({
    required this.label,
    required this.cents,
    required this.type,
  });

  final String label;
  final int cents;
  final _TxType type;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final color = type == _TxType.income
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
  const _CandidateTile({required this.candidate, required this.onToggle});

  final ImportCandidate candidate;
  final ValueChanged<ImportCandidate> onToggle;

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
                      : '第 ${candidate.rowNumber} 行 · '
                          '${candidate.rawSummary}',
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
                      ),
                      if (candidate.status == CandidateStatus.duplicate)
                        _MiniTag(text: '重复', highlight: true),
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
  const _MiniTag({required this.text, this.highlight = false});

  final String text;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          color: highlight
              ? theme.colorScheme.error
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
