import 'package:finance_hub/domain/entities/category_rule.dart';
import 'package:finance_hub/domain/entities/merchant_rule.dart';
import 'package:finance_hub/domain/enums/bill_source.dart';

/// 分类规则仓储接口（由 data 层实现）。
///
/// 规则是**数据**而不是代码（brief 第 11 条），因此修改规则后可以
/// 「重新分类历史账单」，且不影响用户手动指定的分类。
abstract class RuleRepository {
  /// 全部关键词规则（含禁用的，由引擎自行过滤）。
  Future<List<CategoryRule>> loadCategoryRules();

  /// 全部商户记忆。
  Future<List<MerchantRule>> loadMerchantRules();

  /// 记住「这个商户属于哪个分类」—— 分类的第一优先级。
  ///
  /// 用户在导入预览里把某条交易改成别的分类时调用。
  /// 已存在同 (merchantKey, source) 的记录则更新。
  Future<void> rememberMerchant({
    required String merchant,
    required int categoryId,
    BillSource? source,
    int? subcategoryId,
  });

  /// 忘记某个商户的记忆。
  Future<void> forgetMerchant(String merchantKey);

  /// 批量累加命中次数（用于「重新分类」后统计规则热度）。
  Future<void> bumpRuleHits(List<int> ruleIds);
}
