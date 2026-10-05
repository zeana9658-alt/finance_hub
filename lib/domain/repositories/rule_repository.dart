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

  /// 新增关键词规则，返回新 id。
  Future<int> createRule(CategoryRule rule);

  /// 更新关键词规则（按 id）。
  Future<void> updateRule(CategoryRule rule);

  /// 删除规则。**内置规则不允许删除**（只能禁用），
  /// 调用方应先检查 `rule.isBuiltin`。
  Future<void> deleteRule(int id);

  /// 启用/禁用规则。
  Future<void> setRuleEnabled(int id, bool enabled);

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

  /// 清空全部商户记忆。
  Future<void> clearMerchantRules();

  /// 批量累加命中次数（用于「重新分类」后统计规则热度）。
  Future<void> bumpRuleHits(List<int> ruleIds);
}
