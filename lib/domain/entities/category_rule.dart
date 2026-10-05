import 'package:finance_hub/domain/enums/bill_source.dart';
import 'package:finance_hub/domain/enums/transaction_type.dart';

/// 规则的匹配模式。
///
/// 借鉴 `cxy0714/beancount-auto-bookkeeping` 的 `rules.yaml` 里
/// `match_mode: payee_AND_goods` 的设计：单纯的关键词 OR 匹配会把
/// 「会员」这类泛词误伤（影音会员 vs 健身房会员），必须支持组合条件。
enum RuleMatchMode {
  /// 任一已设置条件命中即可。
  any('any', '任一条件'),

  /// 所有已设置条件都需命中。
  all('all', '全部条件'),

  /// 商户与描述必须同时命中（最精确）。
  merchantAndDescription('merchant_and_description', '商户且描述');

  const RuleMatchMode(this.code, this.label);

  final String code;
  final String label;

  static RuleMatchMode fromCode(String? code) {
    if (code == null) {
      return RuleMatchMode.any;
    }
    for (final value in RuleMatchMode.values) {
      if (value.code == code) {
        return value;
      }
    }
    return RuleMatchMode.any;
  }
}

/// 关键词分类规则 —— 分类引擎的**第三优先级**。
///
/// 关键特性（brief 第 11 条）：规则是**数据**而不是代码，
/// 用户修改规则后可以「重新分类历史账单」，且不影响已手动指定的分类。
class CategoryRule {
  const CategoryRule({
    this.id,
    required this.name,
    this.enabled = true,
    this.priority = 100,
    this.source,
    this.merchantContains = const <String>[],
    this.descriptionContains = const <String>[],
    this.amountMinCents,
    this.amountMaxCents,
    this.direction,
    this.matchMode = RuleMatchMode.any,
    required this.targetCategoryId,
    this.targetSubcategoryId,
    this.hitCount = 0,
    this.isBuiltin = false,
  });

  final int? id;
  final String name;
  final bool enabled;

  /// 越小越先匹配。
  final int priority;

  /// 限定来源；`null` 表示不限。
  final BillSource? source;

  final List<String> merchantContains;
  final List<String> descriptionContains;

  final int? amountMinCents;
  final int? amountMaxCents;

  /// 限定收支方向；`null` 表示不限。
  final TransactionType? direction;

  final RuleMatchMode matchMode;

  final int targetCategoryId;
  final int? targetSubcategoryId;

  final int hitCount;

  /// 是否内置规则（内置规则不可删除，只能禁用）。
  final bool isBuiltin;

  CategoryRule copyWith({
    int? id,
    String? name,
    bool? enabled,
    int? priority,
    BillSource? source,
    List<String>? merchantContains,
    List<String>? descriptionContains,
    int? amountMinCents,
    int? amountMaxCents,
    TransactionType? direction,
    RuleMatchMode? matchMode,
    int? targetCategoryId,
    int? targetSubcategoryId,
    int? hitCount,
    bool? isBuiltin,
  }) {
    return CategoryRule(
      id: id ?? this.id,
      name: name ?? this.name,
      enabled: enabled ?? this.enabled,
      priority: priority ?? this.priority,
      source: source ?? this.source,
      merchantContains: merchantContains ?? this.merchantContains,
      descriptionContains: descriptionContains ?? this.descriptionContains,
      amountMinCents: amountMinCents ?? this.amountMinCents,
      amountMaxCents: amountMaxCents ?? this.amountMaxCents,
      direction: direction ?? this.direction,
      matchMode: matchMode ?? this.matchMode,
      targetCategoryId: targetCategoryId ?? this.targetCategoryId,
      targetSubcategoryId: targetSubcategoryId ?? this.targetSubcategoryId,
      hitCount: hitCount ?? this.hitCount,
      isBuiltin: isBuiltin ?? this.isBuiltin,
    );
  }

  @override
  String toString() => 'CategoryRule($name, priority=$priority, mode=${matchMode.code})';
}
