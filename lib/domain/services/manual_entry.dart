import 'dart:math';

import 'package:finance_hub/core/errors/app_error.dart';
import 'package:finance_hub/domain/entities/normalized_transaction.dart';
import 'package:finance_hub/domain/enums/bill_source.dart';
import 'package:finance_hub/domain/enums/category_source.dart';
import 'package:finance_hub/domain/enums/transaction_status.dart';
import 'package:finance_hub/domain/enums/transaction_type.dart';
import 'package:finance_hub/domain/services/transaction_fingerprint.dart';

/// 手动记账。
///
/// 与账单导入的区别（很重要）：
/// 1. **分类来源固定为 `manual`** —— 用户在表单里选的分类就是最终结论，
///    之后「重新分类历史账单」不会碰它（brief 第 11 条的保护机制）。
/// 2. **指纹用生成的唯一单号，而不是内容指纹** —— 同一天手记两笔
///    「示例咖啡 ¥28」是完全合理的，用内容指纹会被误判成重复。
/// 3. `source = manual`，与账单导入的交易在界面上可区分。
class ManualEntry {
  ManualEntry._();

  static final Random _random = Random();

  /// 生成一个唯一的手动记账单号。
  ///
  /// 用「微秒时间戳 + 随机数」而不是纯时间戳：同一微秒内连点两次保存
  /// 也不会撞（虽然实际很难发生，但撞了就是静默丢一笔）。
  static String generateExternalId([DateTime? now]) {
    final stamp = (now ?? DateTime.now()).microsecondsSinceEpoch;
    final noise = _random.nextInt(1 << 20);
    return 'MANUAL-$stamp-$noise';
  }

  /// 构造一笔手动记账交易。
  ///
  /// [amountCents] 必须是正数（界面应先校验并给出可读提示）。
  static NormalizedTransaction build({
    required TransactionType type,
    required int amountCents,
    required DateTime occurredAt,
    int? categoryId,
    int? subcategoryId,
    String merchant = '',
    String note = '',
    String paymentMethod = '',
    String? externalId,
    DateTime? now,
  }) {
    if (amountCents <= 0) {
      throw const AppException(
        '金额必须大于 0',
        detail: '手动记账不允许 0 元或负数金额',
      );
    }
    if (type == TransactionType.transfer || type == TransactionType.refund) {
      throw const AppException(
        '手动记账暂不支持转账 / 退款',
        detail: '请通过账单导入来记录这两类交易',
      );
    }

    final timestamp = now ?? DateTime.now();
    final id = externalId ?? generateExternalId(timestamp);

    return NormalizedTransaction(
      source: BillSource.manual,
      sourceTransactionId: id,
      uniqueKey: TransactionFingerprint.fromExternalId(BillSource.manual, id),
      transactionTime: occurredAt,
      transactionTimeRaw: _formatDateTime(occurredAt),
      transactionType: type,
      transactionTypeRaw: '手动记账',
      amountCents: amountCents,
      merchant: merchant.trim(),
      description: '',
      categoryId: categoryId,
      subcategoryId: subcategoryId,
      // ★ 手动选择的分类受保护，重跑不会覆盖
      categorySource: CategorySource.manual,
      paymentMethod: paymentMethod.trim(),
      status: TransactionStatus.success,
      note: note.trim(),
      createdAt: timestamp,
      updatedAt: timestamp,
    );
  }

  static String _formatDateTime(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
  }
}
