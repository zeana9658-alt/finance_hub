/// 交易类型（归一化后的方向语义）。
///
/// 与数据库 `transactions.transaction_type` 的 CHECK 约束取值一一对应。
///
/// 注意：平台原始的类型文本（如微信的「商户消费」）保存在
/// `NormalizedTransaction.transactionTypeRaw`，不要混用。
enum TransactionType {
  income('income', '收入'),
  expense('expense', '支出'),
  transfer('transfer', '转账'),
  refund('refund', '退款');

  const TransactionType(this.code, this.label);

  final String code;
  final String label;

  /// 是否计入「消费」统计（分类占比、消费日历等）。
  bool get isConsumption => this == TransactionType.expense;

  /// 是否计入「收入」合计。
  bool get countsAsIncome => this == TransactionType.income;

  /// 是否计入「支出」合计。
  ///
  /// 退款也计入支出合计的**冲减项**由聚合层处理，这里只表达方向。
  bool get countsAsExpense =>
      this == TransactionType.expense || this == TransactionType.refund;

  /// 该类型是否默认在导入预览中勾选。
  ///
  /// 转账（资金搬运，如零钱提现、信用卡还款）默认**不勾选**，
  /// 因为它不是消费，计进来会让支出虚高。用户仍可手动勾选。
  bool get defaultSelectedInImport => this != TransactionType.transfer;

  static TransactionType? fromCode(String? code) {
    if (code == null) {
      return null;
    }
    for (final value in TransactionType.values) {
      if (value.code == code) {
        return value;
      }
    }
    return null;
  }

  @override
  String toString() => label;
}
