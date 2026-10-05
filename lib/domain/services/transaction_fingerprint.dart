import 'package:finance_hub/core/utils/hash_utils.dart';
import 'package:finance_hub/core/utils/text_utils.dart';
import 'package:finance_hub/domain/enums/bill_source.dart';

/// 交易去重指纹生成器。
///
/// 这是全项目最关键的算法，实现依据 docs/DATABASE.md §3。
///
/// 规则（按优先级）：
/// 1. 有交易单号 → `src:{source}:{单号}`
/// 2. 无交易单号 → `fp:{sha1(source|time|amount|merchant|description|paymentMethod)}`
///
/// **`source` 必须参与指纹**：这样微信「麦当劳 ¥38」与支付宝「麦当劳 ¥38」
/// 会得到不同的 key，天然不会被误判为重复（brief 第 8 条硬约束）。
class TransactionFingerprint {
  TransactionFingerprint._();

  static const String _sourcePrefix = 'src:';
  static const String _fallbackPrefix = 'fp:';

  /// 基于交易单号生成指纹。
  static String fromExternalId(BillSource source, String externalId) =>
      '$_sourcePrefix${source.code}:${normalizeExternalId(externalId)}';

  /// 基于内容生成回退指纹。
  ///
  /// 字段顺序严格对齐 brief 第 8 条：
  /// `source / transaction_time / amount / merchant / description / payment_method`
  static String fromContent({
    required BillSource source,
    required DateTime transactionTime,
    required int amountCents,
    required String merchant,
    required String description,
    required String paymentMethod,
  }) {
    final parts = <String>[
      source.code,
      transactionTime.millisecondsSinceEpoch.toString(),
      amountCents.toString(),
      normalizeMerchantForFingerprint(merchant),
      normalizeDescriptionForFingerprint(description),
      normalizePaymentMethodForFingerprint(paymentMethod),
    ];
    return '$_fallbackPrefix${sha1Hex(parts.join('|'))}';
  }

  /// 自动选择：有单号用单号，没有则回退到内容指纹。
  static String compute({
    required BillSource source,
    String? externalId,
    required DateTime transactionTime,
    required int amountCents,
    required String merchant,
    required String description,
    required String paymentMethod,
  }) {
    final id = externalId == null ? '' : normalizeExternalId(externalId);
    if (id.isNotEmpty) {
      return fromExternalId(source, id);
    }
    return fromContent(
      source: source,
      transactionTime: transactionTime,
      amountCents: amountCents,
      merchant: merchant,
      description: description,
      paymentMethod: paymentMethod,
    );
  }

  /// 该指纹是否基于交易单号（而非内容回退）。
  static bool isSourceIdBased(String uniqueKey) =>
      uniqueKey.startsWith(_sourcePrefix);

  /// 该指纹是否基于内容回退。
  static bool isContentBased(String uniqueKey) =>
      uniqueKey.startsWith(_fallbackPrefix);
}
