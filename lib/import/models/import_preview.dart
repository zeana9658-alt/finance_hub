import 'package:finance_hub/domain/enums/bill_source.dart';
import 'package:finance_hub/domain/enums/transaction_type.dart';
import 'package:finance_hub/import/detect/source_detector.dart';
import 'package:finance_hub/import/models/import_candidate.dart';

/// 导入预览 —— 用户确认写入数据库之前的**唯一决策依据**。
///
/// 对应 brief 第 6/7 条：选完文件不直接写库，先展示统计与逐条明细。
/// 本对象完全在内存中，用户点「取消」时零副作用。
class ImportPreview {
  const ImportPreview({
    required this.label,
    required this.source,
    required this.detectionBasis,
    required this.createdAt,
    required this.candidates,
    required this.totalDataRows,
    this.headerRowNumber,
    this.filePath,
    this.fileHash,
  });

  /// 文件显示名或「粘贴文本」。
  final String label;

  /// 识别出的来源。无法识别时由 UI 让用户手动选择后再构造预览。
  final BillSource source;

  final DetectionBasis detectionBasis;

  final DateTime createdAt;

  final List<ImportCandidate> candidates;

  /// 数据区总行数（不含表头与说明行）。
  final int totalDataRows;

  /// 表头行号（1-based），排查用。
  final int? headerRowNumber;

  final String? filePath;

  /// 文件内容 sha1，用于提示「该文件已导入过」。
  final String? fileHash;

  // ───────────────────────── 统计口径 ─────────────────────────

  int get totalCount => candidates.length;

  int get validCount => candidates
      .where((candidate) => candidate.status == CandidateStatus.valid)
      .length;

  int get duplicateCount => candidates
      .where((candidate) => candidate.status == CandidateStatus.duplicate)
      .length;

  int get errorCount => candidates
      .where((candidate) => candidate.status == CandidateStatus.error)
      .length;

  int get suspectedCrossPlatformCount => candidates
      .where((candidate) => candidate.isSuspectedCrossPlatform)
      .length;

  /// 当前勾选且可导入的候选。
  List<ImportCandidate> get selectedCandidates => candidates
      .where((candidate) => candidate.isSelected && candidate.transaction != null)
      .toList(growable: false);

  int get selectedCount => selectedCandidates.length;

  /// 勾选项的收入合计（分）。
  int get selectedIncomeCents => _sumByType(TransactionType.income);

  /// 勾选项的支出合计（分）。
  int get selectedExpenseCents => _sumByType(TransactionType.expense);

  /// 全部可导入项的收入合计（分）。
  int get allIncomeCents => _sumByType(TransactionType.income, onlySelected: false);

  /// 全部可导入项的支出合计（分）。
  int get allExpenseCents =>
      _sumByType(TransactionType.expense, onlySelected: false);

  int _sumByType(TransactionType type, {bool onlySelected = true}) {
    var total = 0;
    for (final candidate in candidates) {
      final tx = candidate.transaction;
      if (tx == null || tx.transactionType != type) {
        continue;
      }
      if (candidate.status == CandidateStatus.error) {
        continue;
      }
      if (onlySelected && !candidate.isSelected) {
        continue;
      }
      total += tx.amountCents;
    }
    return total;
  }

  /// 按状态筛选。
  List<ImportCandidate> filterBy(CandidateStatus? status) => status == null
      ? candidates
      : candidates
          .where((candidate) => candidate.status == status)
          .toList(growable: false);

  ImportPreview copyWith({
    List<ImportCandidate>? candidates,
    BillSource? source,
    DetectionBasis? detectionBasis,
  }) {
    return ImportPreview(
      label: label,
      source: source ?? this.source,
      detectionBasis: detectionBasis ?? this.detectionBasis,
      createdAt: createdAt,
      candidates: candidates ?? this.candidates,
      totalDataRows: totalDataRows,
      headerRowNumber: headerRowNumber,
      filePath: filePath,
      fileHash: fileHash,
    );
  }

  @override
  String toString() =>
      'ImportPreview($label, ${source.code}, 可导入 $validCount / '
      '重复 $duplicateCount / 异常 $errorCount)';
}
