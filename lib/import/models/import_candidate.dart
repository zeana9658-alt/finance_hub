import 'package:finance_hub/domain/entities/normalized_transaction.dart';

/// 候选行的状态。
enum CandidateStatus {
  /// 可导入（默认勾选）。
  valid('valid', '可导入'),

  /// 重复（默认不勾选）。
  duplicate('duplicate', '重复'),

  /// 数据异常（不可勾选）。
  error('error', '数据异常');

  const CandidateStatus(this.code, this.label);

  final String code;
  final String label;
}

/// 导入预览中的一条候选。
///
/// 三种状态对应 brief 第 7 条预览页的「✓ 可导入 / ↻ 重复 / ! 数据异常」。
///
/// [isSelected] 是可变语义（通过 [copyWith] 更新），让用户在写库前自由勾选。
class ImportCandidate {
  const ImportCandidate({
    required this.index,
    required this.status,
    this.transaction,
    required this.rowNumber,
    required this.rawSummary,
    this.errorReason = '',
    this.isSuspectedCrossPlatform = false,
    this.categoryLabel = '',
    this.isSelected = false,
  });

  /// 在预览列表中的稳定下标。
  final int index;

  final CandidateStatus status;

  /// 归一化后的交易。**错误行没有交易**，此处为 `null`。
  final NormalizedTransaction? transaction;

  /// 在原始文件中的行号（1-based）。
  final int rowNumber;

  /// 原始内容摘要，用于错误行与列表副标题。
  final String rawSummary;

  /// 错误原因（仅 [CandidateStatus.error]）。
  final String errorReason;

  /// 疑似跨平台重复 —— 仍默认勾选，只给黄色提示。
  final bool isSuspectedCrossPlatform;

  /// 分类展示文案，如 `餐饮 / 咖啡茶饮`。
  final String categoryLabel;

  /// 是否勾选（仅对 [CandidateStatus.valid] 有意义）。
  final bool isSelected;

  bool get isSelectable => status != CandidateStatus.error;

  ImportCandidate copyWith({
    CandidateStatus? status,
    NormalizedTransaction? transaction,
    String? errorReason,
    bool? isSuspectedCrossPlatform,
    String? categoryLabel,
    bool? isSelected,
  }) {
    return ImportCandidate(
      index: index,
      status: status ?? this.status,
      transaction: transaction ?? this.transaction,
      rowNumber: rowNumber,
      rawSummary: rawSummary,
      errorReason: errorReason ?? this.errorReason,
      isSuspectedCrossPlatform:
          isSuspectedCrossPlatform ?? this.isSuspectedCrossPlatform,
      categoryLabel: categoryLabel ?? this.categoryLabel,
      isSelected: isSelected ?? this.isSelected,
    );
  }

  @override
  String toString() =>
      'ImportCandidate(#$index, ${status.code}, row=$rowNumber, selected=$isSelected)';
}
