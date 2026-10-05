/// 交易状态。
///
/// 与数据库 `transactions.status` 的 CHECK 约束取值一一对应。
///
/// [defaultSelected] 决定该状态在导入预览中是否默认勾选 ——
/// 「已关闭 / 失败 / 处理中」的交易不应计入账本。
enum TransactionStatus {
  success('success', '成功', true),
  refunded('refunded', '已退款', true),
  pending('pending', '处理中', false),
  closed('closed', '已关闭', false),
  failed('failed', '失败', false);

  const TransactionStatus(this.code, this.label, this.defaultSelected);

  final String code;
  final String label;

  /// 导入预览中默认是否勾选。
  final bool defaultSelected;

  static TransactionStatus? fromCode(String? code) {
    if (code == null) {
      return null;
    }
    for (final value in TransactionStatus.values) {
      if (value.code == code) {
        return value;
      }
    }
    return null;
  }

  @override
  String toString() => label;
}
