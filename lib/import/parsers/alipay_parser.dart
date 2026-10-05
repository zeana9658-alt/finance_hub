import 'package:finance_hub/core/errors/app_error.dart';
import 'package:finance_hub/domain/entities/normalized_transaction.dart';
import 'package:finance_hub/domain/enums/bill_source.dart';
import 'package:finance_hub/domain/enums/transaction_status.dart';
import 'package:finance_hub/domain/enums/transaction_type.dart';
import 'package:finance_hub/import/models/raw_bill_row.dart';
import 'package:finance_hub/import/parsers/bill_parser.dart';

/// 支付宝账单解析器。
///
/// 同时支持两个导出版本（见 docs/IMPORT_FORMATS.md §4.1）：
///
/// **版本 A（网页导出，CSV，GBK 编码）**
/// ```text
/// 交易号,商家订单号,交易创建时间,付款时间,最近修改时间,交易来源地,类型,交易对方,
/// 商品名称,金额（元）,收/支,交易状态,服务费（元）,成功退款（元）,备注,资金状态
/// ```
///
/// **版本 B（App 导出）**
/// ```text
/// 交易时间,交易分类,交易对方,商品说明,收/支,金额,支付方式,交易状态,交易订单号,商家订单号,备注
/// ```
///
/// 两个版本的差异全部由 `HeaderLocator` + `ColumnAliases` 消化，
/// 本类不需要区分版本 —— 这是「表头驱动而非行号驱动」带来的好处。
class AlipayParser extends BillParser {
  AlipayParser();

  @override
  BillSource get source => BillSource.alipay;

  /// 资金搬运类交易。
  ///
  /// 支付宝的「类型」列取值通常是「即时到账 / 担保交易」这类，
  /// 真正需要排除的信息在「交易分类」里，因此这里只覆盖明确的关键词。
  @override
  List<String> get excludeTypeKeywords => const <String>[
        '提现',
        '充值',
        '还款',
        '余额宝',
        '转账',
      ];

  @override
  NormalizedTransaction? normalizeRow(RawBillRow row) {
    final amountCents = requireAmountCents(row.amountText);
    if (amountCents == 0) {
      throw const ParseException('金额为 0，跳过');
    }

    final transactionTime = requireDateTime(row.timeText);
    final status = mapStatus(row.statusText);
    final transactionType = mapDirection(row, status);

    final merchant = row.merchantText.isEmpty
        ? BillSource.alipay.label
        : row.merchantText;

    return buildTransaction(
      source: BillSource.alipay,
      sourceTransactionId: row.externalIdText,
      transactionTime: transactionTime,
      transactionTimeRaw: row.timeText,
      transactionType: transactionType,
      transactionTypeRaw: row.typeText.isEmpty
          ? row.categoryText
          : row.typeText,
      platformCategory: row.categoryText,
      amountCents: amountCents,
      merchant: merchant,
      description: cleanField(row.descriptionText),
      paymentMethod: row.paymentMethodText.isEmpty
          ? '支付宝'
          : row.paymentMethodText,
      status: status,
      note: cleanNote(row.noteText),
      row: row,
    );
  }

  /// 状态映射。
  TransactionStatus mapStatus(String raw) {
    final s = raw.trim();
    if (s.isEmpty) {
      return TransactionStatus.success;
    }
    if (s.contains('退款')) {
      return TransactionStatus.refunded;
    }
    if (s.contains('关闭') || s.contains('已取消')) {
      return TransactionStatus.closed;
    }
    if (s.contains('失败')) {
      return TransactionStatus.failed;
    }
    if (s.contains('等待') || s.contains('处理中') || s.contains('进行中')) {
      return TransactionStatus.pending;
    }
    // 「交易成功」「交易完成」「已收款」等
    return TransactionStatus.success;
  }

  /// 方向映射。
  ///
  /// ⚠️ 这里必须**显式处理「不计收支」三分支**。
  /// 参考项目 `zalexrose/FamilyFinanceManager` 的写法是
  /// `if "支出" in trans_type: 负数 else: 正数`，
  /// 会把「不计收支」误判为收入，导致收支方向错误。
  TransactionType mapDirection(RawBillRow row, TransactionStatus status) {
    // 资金搬运优先：交易分类/类型命中「转账/提现/充值/还款」等
    if (isTransferType(row.typeText) || isTransferType(row.categoryText)) {
      return TransactionType.transfer;
    }
    if (status == TransactionStatus.refunded) {
      return TransactionType.refund;
    }

    final d = row.directionText.trim();

    if (d.contains('不计')) {
      return TransactionType.transfer;
    }
    if (d.contains('支出')) {
      return TransactionType.expense;
    }
    if (d.contains('收入')) {
      return TransactionType.income;
    }
    if (d == '/' || d == '-' || d.isEmpty) {
      // 方向缺失：结合交易分类与状态推断，推断不出就报错（不猜）。
      if (isRefundType(row.typeText) ||
          isRefundType(row.categoryText) ||
          status == TransactionStatus.refunded) {
        return TransactionType.refund;
      }
      if (isTransferType(row.typeText) || isTransferType(row.categoryText)) {
        return TransactionType.transfer;
      }
      throw ParseException('无法识别收/支方向', detail: row.rawSummary);
    }

    if (isRefundType(row.typeText) || isRefundType(row.categoryText)) {
      return TransactionType.refund;
    }
    throw ParseException('无法识别收/支方向', detail: d);
  }
}
