import 'package:finance_hub/core/utils/text_utils.dart';
import 'package:finance_hub/domain/enums/bill_source.dart';

/// 商户记忆 —— 分类引擎的**第一优先级**。
///
/// 用户在导入预览里把「Lawson」改成「餐饮 / 便利店」后，这条记忆被写入本表；
/// 之后所有 Lawson 交易自动归类，`category_source = merchant_memory`。
///
/// 对应 brief 第 9 条的第三级「商户记忆规则」与第 10 条的第一优先级。
class MerchantRule {
  const MerchantRule({
    this.id,
    required this.merchantDisplay,
    required this.categoryId,
    this.merchantKey,
    this.source,
    this.subcategoryId,
    this.confidence = 100,
    this.appliedCount = 0,
    this.lastAppliedAt,
  });

  final int? id;

  /// 展示名（用户看到的样子，如 `Lawson 罗森`）。
  final String merchantDisplay;

  /// 归一化键。为空时由 [merchantDisplay] 计算。
  final String? merchantKey;

  /// 限定来源；`null` 表示不限（`any`）。
  final BillSource? source;

  final int categoryId;
  final int? subcategoryId;

  /// 置信度 0~100。
  final int confidence;

  final int appliedCount;
  final DateTime? lastAppliedAt;

  /// 实际用于匹配的键。
  String get key => merchantKey ?? merchantKeyOf(merchantDisplay);

  /// 来源编码，`null` 对应数据库的 `'any'`。
  String get sourceCode => source?.code ?? 'any';

  MerchantRule copyWith({
    int? id,
    String? merchantDisplay,
    String? merchantKey,
    BillSource? source,
    int? categoryId,
    int? subcategoryId,
    int? confidence,
    int? appliedCount,
    DateTime? lastAppliedAt,
  }) {
    return MerchantRule(
      id: id ?? this.id,
      merchantDisplay: merchantDisplay ?? this.merchantDisplay,
      merchantKey: merchantKey ?? this.merchantKey,
      source: source ?? this.source,
      categoryId: categoryId ?? this.categoryId,
      subcategoryId: subcategoryId ?? this.subcategoryId,
      confidence: confidence ?? this.confidence,
      appliedCount: appliedCount ?? this.appliedCount,
      lastAppliedAt: lastAppliedAt ?? this.lastAppliedAt,
    );
  }

  @override
  String toString() =>
      'MerchantRule($merchantDisplay -> category=$categoryId, sub=$subcategoryId, src=$sourceCode)';
}
