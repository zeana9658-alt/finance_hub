import 'package:finance_hub/core/errors/app_error.dart';
import 'package:finance_hub/domain/entities/normalized_transaction.dart';
import 'package:finance_hub/domain/enums/bill_source.dart';
import 'package:finance_hub/domain/enums/transaction_status.dart';
import 'package:finance_hub/domain/enums/transaction_type.dart';
import 'package:finance_hub/import/models/raw_bill_row.dart';
import 'package:finance_hub/import/parsers/bill_parser.dart';

/// 微信支付账单解析器。
///
/// 表头（见 docs/IMPORT_FORMATS.md §3.1）：
/// ```text
/// 交易时间,交易类型,交易对方,商品,收/支,金额(元),支付方式,当前状态,交易单号,商户单号,备注
/// ```
class WechatParser extends BillParser {
  WechatParser();

  @override
  BillSource get source => BillSource.wechat;

  /// 资金搬运类交易 —— 不是消费，计进支出会严重虚高。
  ///
  /// 来源：`zalexrose/FamilyFinanceManager` 的 `exclude_types`。
  /// 处理方式是**标记为 transfer 并默认不勾选**，而不是静默丢弃。
  @override
  List<String> get excludeTypeKeywords => const <String>[
        '零钱提现',
        '零钱充值',
        '转入零钱通',
        '零钱通转出',
        '转账',
        '信用卡还款',
        '理财通',
        '零钱通',
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

    final merchantRaw = cleanField(row.merchantText);
    final merchant =
        merchantRaw.isEmpty ? BillSource.wechat.label : merchantRaw;
    final description = cleanField(row.descriptionText);

    return buildTransaction(
      source: BillSource.wechat,
      sourceTransactionId: row.externalIdText,
      transactionTime: transactionTime,
      transactionTimeRaw: row.timeText,
      transactionType: transactionType,
      transactionTypeRaw: row.typeText,
      amountCents: amountCents,
      merchant: merchant,
      description: description,
      paymentMethod: row.paymentMethodText.isEmpty
          ? '微信零钱'
          : row.paymentMethodText,
      status: status,
      note: cleanNote(row.noteText),
      row: row,
    );
  }

  /// 状态映射。
  ///
  /// 判定顺序很重要：`已全额退款` 同时含「退款」与「成功」，
  /// 必须先判退款，否则会被误判成普通成功交易。
  TransactionStatus mapStatus(String raw) {
    final s = raw.trim();
    if (s.isEmpty) {
      return TransactionStatus.success;
    }
    if (s.contains('退款') || s.contains('已退还')) {
      return TransactionStatus.refunded;
    }
    if (s.contains('关闭') || s.contains('取消')) {
      return TransactionStatus.closed;
    }
    if (s.contains('失败')) {
      return TransactionStatus.failed;
    }
    if (s.contains('处理中') || s.contains('等待') || s.contains('进行中')) {
      return TransactionStatus.pending;
    }
    // 「支付成功」「已转账」「已存入零钱」「对方已收钱」等一律视为成功。
    // 未知文本也按成功处理 —— 丢掉用户数据的代价比误判状态更大。
    return TransactionStatus.success;
  }

  /// 方向映射。
  ///
  /// 判定顺序：资金搬运 → 已退款 → 交易类型为退款 → 收/支文本。
  ///
  /// 「已全额退款」的行在微信账单里 `收/支` 仍可能是「支出」，
  /// 但语义上钱已经回来了，因此归为 [TransactionType.refund]。
  TransactionType mapDirection(RawBillRow row, TransactionStatus status) {
    if (isTransferType(row.typeText)) {
      return TransactionType.transfer;
    }
    if (status == TransactionStatus.refunded) {
      return TransactionType.refund;
    }
    if (isRefundType(row.typeText)) {
      return TransactionType.refund;
    }

    final d = row.directionText.trim();
    if (d.contains('支出') || d.contains('付款')) {
      return TransactionType.expense;
    }
    if (d.contains('收入') || d.contains('收款')) {
      return TransactionType.income;
    }
    if (d.contains('不计') || d == '/' || d == '-' || d.isEmpty) {
      // 微信「/」表示不计收支；结合状态判断是否为退款。
      return status == TransactionStatus.refunded
          ? TransactionType.refund
          : TransactionType.transfer;
    }
    // 兜底：文本里明确含「退款」才当退款，否则当支出。
    return d.contains('退款') ? TransactionType.refund : TransactionType.expense;
  }
}
