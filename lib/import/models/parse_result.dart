import 'package:finance_hub/domain/entities/normalized_transaction.dart';
import 'package:finance_hub/import/models/parse_error.dart';

/// 一条解析成功的交易 + 它在原始文件中的位置。
///
/// 携带 [rowNumber] 是为了让导入预览能**按原始行号排序**，
/// 这样错误行与成功行可以交错展示，用户核对时不会跳来跳去。
class ParsedTransaction {
  const ParsedTransaction({
    required this.rowNumber,
    required this.transaction,
    this.rawSummary = '',
  });

  /// 在原始文件中的行号（1-based）。
  final int rowNumber;

  final NormalizedTransaction transaction;

  /// 原始内容摘要（前几列），列表副标题用。
  final String rawSummary;

  @override
  String toString() => 'ParsedTransaction(#$rowNumber, $transaction)';
}

/// 一次解析的完整结果。
///
/// **不丢弃任何信息**：解析成功的交易进 [parsed]，
/// 解析失败的行进 [errors]，两者都返回给上层。
/// 这与参考项目「静默 continue 丢行」的做法有本质区别（brief 第 30 条）。
class ParseResult {
  const ParseResult({
    required this.parsed,
    required this.errors,
    required this.totalDataRows,
    this.headerRowNumber,
  });

  /// 解析成功的交易（尚未判重、尚未分类），带原始行号。
  final List<ParsedTransaction> parsed;

  /// 解析失败的行。
  final List<ParseError> errors;

  /// 数据区总行数（不含表头与说明行）。
  final int totalDataRows;

  /// 表头所在行号（1-based），排查用。
  final int? headerRowNumber;

  /// 便捷访问：仅交易列表。
  List<NormalizedTransaction> get transactions =>
      parsed.map((item) => item.transaction).toList(growable: false);

  bool get hasErrors => errors.isNotEmpty;

  int get successCount => parsed.length;

  int get errorCount => errors.length;

  static const ParseResult empty = ParseResult(
    parsed: <ParsedTransaction>[],
    errors: <ParseError>[],
    totalDataRows: 0,
  );

  @override
  String toString() =>
      'ParseResult(成功 ${parsed.length} / 错误 ${errors.length} / 数据行 $totalDataRows)';
}
