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

  /// 进程内自增序号。
  ///
  /// **不能只靠「时间戳 + 随机数」**：Windows 上 `DateTime.now()` 的实际分辨率
  /// 约 1ms（部分环境甚至 15ms），密集调用时 `microsecondsSinceEpoch` 几乎不变，
  /// 只剩随机段能区分。原来随机段只有 20 位（2^20），批量生成 500 个单号时
  /// 按生日悖论约有 **11%** 概率撞号 —— 实测在干净克隆里真的撞了，
  /// 表现为 `generateExternalId 不重复` 偶发失败。
  ///
  /// 撞号的后果不是"测试变红"，而是**静默丢一笔**：`uniqueKey` 由单号派生，
  /// 撞号的两笔会被唯一索引当成重复，第二笔直接写不进去。
  /// 所以这里用序号把「同进程内绝不重复」升级为**确定性保证**，
  /// 随机段只负责跨进程（多实例、重启后同刻、系统时钟回拨）的兜底。
  static int _sequence = 0;

  /// 生成一个唯一的手动记账单号。
  ///
  /// 形如 `MANUAL-<微秒时间戳>-<进程内序号>-<随机数>`。
  /// 保留时间戳是为了可读、可按时间排序，便于排查问题；
  /// 没有任何代码解析这个格式，它只作为字符串参与指纹哈希。
  static String generateExternalId([DateTime? now]) {
    final stamp = (now ?? DateTime.now()).microsecondsSinceEpoch;
    final sequence = _sequence++;
    final noise = _random.nextInt(1 << 30);
    return 'MANUAL-$stamp-$sequence-$noise';
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
