/// 从原始表格行中抽出的语义字段。
///
/// 这是「表格」与「解析」之间的边界：
/// - 上游（[RawTable] + [LocatedHeader]）负责把列位置找对
/// - 这里负责把值取出来
/// - 下游（`BillParser.normalizeRow`）负责把值变成 [NormalizedTransaction]
///
/// 这样每个来源的 Parser 只需要关心「怎么把值解释成交易」，
/// 不必重复处理列定位。
class RawBillRow {
  const RawBillRow({
    required this.rowNumber,
    required this.rawCells,
    this.timeText = '',
    this.typeText = '',
    this.merchantText = '',
    this.descriptionText = '',
    this.directionText = '',
    this.amountText = '',
    this.paymentMethodText = '',
    this.statusText = '',
    this.externalIdText = '',
    this.noteText = '',
    this.categoryText = '',
  });

  /// 在原始文件中的行号（1-based）。
  final int rowNumber;

  /// 该行所有单元格原文。
  final List<String> rawCells;

  final String timeText;
  final String typeText;
  final String merchantText;
  final String descriptionText;
  final String directionText;
  final String amountText;
  final String paymentMethodText;
  final String statusText;
  final String externalIdText;
  final String noteText;
  final String categoryText;

  /// 整行是否为空（用于跳过空行）。
  bool get isBlank => rawCells.every((cell) => cell.trim().isEmpty);

  /// 是否是分隔线行，如 `----------------------交易记录明细列表----------------------`。
  ///
  /// 支付宝 CSV 末尾会有这样一行，不是数据。
  bool get isSeparator {
    final joined = rawCells.join().trim();
    if (joined.isEmpty) {
      return false;
    }
    return RegExp(r'^[-—=*_·・\s]+$').hasMatch(joined);
  }

  /// 原始内容摘要，用于错误提示与预览列表（取前 4 个非空单元格）。
  String get rawSummary => rawCells
      .where((cell) => cell.trim().isNotEmpty)
      .take(4)
      .map((cell) => cell.trim())
      .join(' / ');

  @override
  String toString() => 'RawBillRow(#$rowNumber, $rawSummary)';
}
