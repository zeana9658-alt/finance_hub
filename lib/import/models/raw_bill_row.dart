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

  /// 是否是分隔线行。
  ///
  /// 微信/支付宝账单的首尾会有这种行：
  /// ```text
  /// ----------------------微信支付账单明细列表--------------------
  /// ---------------------------------交易记录明细列表结束---------------------------------
  /// ```
  /// 它们**中间夹着中文**，所以不能只判断「整行是否全是符号」。
  ///
  /// 判定条件（两个都要满足，避免误伤正常数据）：
  /// 1. 非空单元格数 ≤ 2（分隔行通常只有一个单元格）
  /// 2. 存在 5 个以上连续横线 / 等号
  bool get isSeparator {
    final nonEmpty = rawCells.where((cell) => cell.trim().isNotEmpty).length;
    if (nonEmpty == 0 || nonEmpty > 2) {
      return false;
    }
    final joined = rawCells.join().trim();
    return RegExp(r'[-—=]{5,}').hasMatch(joined);
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
