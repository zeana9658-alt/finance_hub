/// 账单来源。
///
/// 每个来源对应一个 [BillParser] 实现（见 lib/import/parsers/）。
/// `code` 与数据库 `transactions.source` 的 CHECK 约束取值一一对应。
enum BillSource {
  wechat('wechat', '微信支付'),
  alipay('alipay', '支付宝'),
  bank('bank', '银行卡'),
  creditCard('credit_card', '信用卡'),
  jd('jd', '京东'),
  manual('manual', '手动记账');

  const BillSource(this.code, this.label);

  /// 持久化用编码（与 DB CHECK 约束一致）。
  final String code;

  /// 界面展示名。
  final String label;

  /// 目前真正实现了 Parser 的来源。
  bool get isImportable => this != BillSource.manual;

  static BillSource? fromCode(String? code) {
    if (code == null) {
      return null;
    }
    for (final value in BillSource.values) {
      if (value.code == code) {
        return value;
      }
    }
    return null;
  }

  @override
  String toString() => label;
}
