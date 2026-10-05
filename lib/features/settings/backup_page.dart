import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:finance_hub/app/providers.dart';
import 'package:finance_hub/app/theme/app_colors.dart';
import 'package:finance_hub/core/errors/app_error.dart';
import 'package:finance_hub/domain/services/backup_service.dart';
import 'package:finance_hub/shared/widgets/app_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 备份与恢复页 —— brief 第 23 条。
///
/// 两条硬约束：
/// 1. **导出默认不含 `raw_data`**（原始账单行），需要用户显式勾选才包含
/// 2. **恢复前必须预览 + 确认**，默认模式是「合并」而不是「覆盖」
class BackupPage extends ConsumerStatefulWidget {
  const BackupPage({super.key});

  @override
  ConsumerState<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends ConsumerState<BackupPage> {
  bool _includeRawData = false;
  bool _busy = false;
  String? _lastExportInfo;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('备份与恢复')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppDimens.pagePadding,
          AppDimens.gapS,
          AppDimens.pagePadding,
          AppDimens.gapXl,
        ),
        children: <Widget>[
          // ─────────────── 导出 ───────────────
          SectionHeader('导出'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '完整备份（JSON）',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: AppDimens.gapXs),
                Text(
                  '包含交易、分类、分类规则、商户记忆、预算与设置。'
                  '恢复时可选「合并」或「覆盖」。',
                  style: theme.textTheme.labelSmall,
                ),
                const SizedBox(height: AppDimens.gapM),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _includeRawData,
                  onChanged: (value) =>
                      setState(() => _includeRawData = value),
                  title: Text(
                    '包含原始数据（不推荐）',
                    style: theme.textTheme.bodySmall,
                  ),
                  subtitle: Text(
                    '勾选后备份里会带上账单原始行，可能包含商户与订单号等细节',
                    style: theme.textTheme.labelSmall,
                  ),
                ),
                const SizedBox(height: AppDimens.gapM),
                FilledButton.icon(
                  onPressed: _busy ? null : _exportJson,
                  icon: const Icon(Icons.file_download_outlined, size: 18),
                  label: const Text('导出完整备份'),
                ),
                const SizedBox(height: AppDimens.gapM),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _exportCsv,
                  icon: const Icon(Icons.table_chart_outlined, size: 18),
                  label: const Text('导出交易明细 CSV'),
                ),
                if (_lastExportInfo != null) ...<Widget>[
                  const SizedBox(height: AppDimens.gapM),
                  Row(
                    children: <Widget>[
                      Icon(
                        Icons.check_circle_outline,
                        size: 16,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _lastExportInfo!,
                          style: theme.textTheme.labelSmall,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppDimens.gapL),

          // ─────────────── 恢复 ───────────────
          SectionHeader('恢复'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('从备份恢复', style: theme.textTheme.bodyMedium),
                const SizedBox(height: AppDimens.gapXs),
                Text(
                  '选择之前导出的 JSON 备份文件。恢复前会先展示备份内容与当前数据量，'
                  '由你确认后再写入。',
                  style: theme.textTheme.labelSmall,
                ),
                const SizedBox(height: AppDimens.gapM),
                FilledButton.tonalIcon(
                  onPressed: _busy ? null : _importBackup,
                  icon: const Icon(Icons.file_upload_outlined, size: 18),
                  label: const Text('选择备份文件'),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppDimens.gapL),

          // ─────────────── 隐私提示 ───────────────
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(
                      Icons.lock_outline,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Text('关于备份文件', style: theme.textTheme.bodyMedium),
                  ],
                ),
                const SizedBox(height: AppDimens.gapS),
                Text(
                  '· 备份文件是**明文**的，请自行妥善保管\n'
                  '· 备份不会自动上传到任何服务器，位置由你在保存对话框里选择\n'
                  '· 银行卡号只存掩码，因此备份里也不会有完整卡号\n'
                  '· 默认不包含账单原始行',
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────── 导出 ─────────────────────────

  Future<void> _exportJson() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final service = ref.read(backupServiceProvider);
      final content = await service.exportJson(includeRawData: _includeRawData);
      final bytes = Uint8List.fromList(utf8.encode(content));
      final name = 'finance_hub_backup_${_timestamp()}.json';

      final uri = await FilePicker.saveFile(
        fileName: name,
        bytes: bytes,
        mimeType: 'application/json',
        dialogTitle: '保存备份文件',
      );

      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _lastExportInfo = uri == null
            ? '已取消保存'
            : '已导出 $name（${_formatBytes(bytes.length)}）';
      });
    } on Exception catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(content: Text('导出失败：$error')));
    }
  }

  Future<void> _exportCsv() async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final service = ref.read(backupServiceProvider);
      final content = await service.exportCsv();
      // 加 UTF-8 BOM，让 Excel 正确识别中文
      final bytes = Uint8List.fromList(
        <int>[0xEF, 0xBB, 0xBF, ...utf8.encode(content)],
      );
      final name = 'finance_hub_transactions_${_timestamp()}.csv';

      final uri = await FilePicker.saveFile(
        fileName: name,
        bytes: bytes,
        mimeType: 'text/csv',
        dialogTitle: '保存 CSV 文件',
      );

      if (!mounted) {
        return;
      }
      setState(() {
        _busy = false;
        _lastExportInfo = uri == null
            ? '已取消保存'
            : '已导出 $name（${_formatBytes(bytes.length)}）';
      });
    } on Exception catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(content: Text('导出失败：$error')));
    }
  }

  // ───────────────────────── 恢复 ─────────────────────────

  Future<void> _importBackup() async {
    final messenger = ScaffoldMessenger.of(context);

    final List<PlatformFile> picked;
    try {
      picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: <String>['json'],
      );
    } on Exception catch (error) {
      messenger.showSnackBar(SnackBar(content: Text('打开文件失败：$error')));
      return;
    }
    if (picked.isEmpty) {
      return;
    }

    setState(() => _busy = true);
    try {
      final bytes = await picked.first.xFile.readAsBytes();
      final service = ref.read(backupServiceProvider);
      final bundle = service.parseJson(utf8.decode(bytes));
      final preview = await service.preview(bundle);

      if (!mounted) {
        return;
      }
      setState(() => _busy = false);

      final mode = await _showRestoreDialog(preview);
      if (mode == null || !mounted) {
        return;
      }
      await _runRestore(service, bundle, mode);
    } on AppException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(content: Text(error.toString())));
    } on Exception catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(content: Text('读取备份失败：$error')));
    }
  }

  Future<RestoreMode?> _showRestoreDialog(BackupPreview preview) {
    RestoreMode selected = RestoreMode.merge;

    return showDialog<RestoreMode>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final theme = Theme.of(context);
          return AlertDialog(
            title: const Text('确认恢复'),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text('备份内容', style: theme.textTheme.titleMedium),
                  const SizedBox(height: AppDimens.gapS),
                  _PreviewRow('交易', '${preview.transactionCount} 条'),
                  _PreviewRow('分类', '${preview.categoryCount} 个'),
                  _PreviewRow('分类规则', '${preview.ruleCount} 条'),
                  _PreviewRow('商户记忆', '${preview.merchantRuleCount} 条'),
                  _PreviewRow('预算', '${preview.budgetCount} 条'),
                  _PreviewRow('备份时间', _formatDateTime(preview.exportedAt)),
                  _PreviewRow('应用版本', preview.appVersion),
                  _PreviewRow(
                    '原始数据',
                    preview.includesRawData ? '包含' : '不含',
                  ),
                  const SizedBox(height: AppDimens.gapM),
                  const Divider(height: 1),
                  const SizedBox(height: AppDimens.gapM),
                  Text(
                    '当前库已有交易 ${preview.currentTransactionCount} 条',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: AppDimens.gapM),
                  Text('恢复方式', style: theme.textTheme.titleMedium),
                  const SizedBox(height: AppDimens.gapS),
                  RadioGroup<RestoreMode>(
                    groupValue: selected,
                    onChanged: (value) => setDialogState(
                      () => selected = value ?? RestoreMode.merge,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        RadioListTile<RestoreMode>(
                          contentPadding: EdgeInsets.zero,
                          value: RestoreMode.merge,
                          title: Text(
                            RestoreMode.merge.label,
                            style: theme.textTheme.bodySmall,
                          ),
                          subtitle: Text(
                            '不会删除现有数据，重复交易自动跳过',
                            style: theme.textTheme.labelSmall,
                          ),
                        ),
                        RadioListTile<RestoreMode>(
                          contentPadding: EdgeInsets.zero,
                          value: RestoreMode.overwrite,
                          title: Text(
                            RestoreMode.overwrite.label,
                            style: theme.textTheme.bodySmall,
                          ),
                          subtitle: Text(
                            '现有交易会被标记为已删除（可在数据库层面恢复）',
                            style: theme.textTheme.labelSmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(selected),
                child: const Text('开始恢复'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _runRestore(
    BackupService service,
    BackupBundle bundle,
    RestoreMode mode,
  ) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await service.restore(bundle, mode: mode);
      if (!mounted) {
        return;
      }
      _invalidateAll();
      setState(() => _busy = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '恢复完成：新增 ${result.insertedTransactions} 条，'
            '跳过 ${result.skippedTransactions} 条，'
            '预算 ${result.restoredBudgets} 条',
          ),
        ),
      );
    } on Exception catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _busy = false);
      messenger.showSnackBar(SnackBar(content: Text('恢复失败：$error')));
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
      ..invalidate(allCategoriesProvider)
      ..invalidate(categoryNameMapProvider)
      ..invalidate(earliestTransactionProvider);
  }

  String _timestamp() {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}_'
        '${two(now.hour)}${two(now.minute)}';
  }

  String _formatDateTime(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}';
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB';
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label, style: theme.textTheme.bodySmall)),
          Text(
            value,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
