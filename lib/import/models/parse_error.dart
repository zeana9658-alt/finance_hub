/// 单行解析错误 —— 必须可见、可追溯（brief 第 30 条）。
///
/// 三元组：第几行 / 原始内容 / 错误原因。
class ParseError {
  const ParseError({
    required this.rowNumber,
    required this.rawSummary,
    required this.reason,
    this.rawJson,
  });

  /// 在**原始文件**中的行号（1-based），方便用户去文件里核对。
  final int rowNumber;

  /// 原始内容摘要（前几列拼接），UI 直接展示。
  final String rawSummary;

  /// 可读的失败原因，例如「金额字段无法解析：待确认」。
  final String reason;

  /// 完整原始行 JSON（可选），本地留档用。
  final String? rawJson;

  @override
  String toString() => '第 $rowNumber 行：$reason';
}
