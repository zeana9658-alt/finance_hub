import 'package:finance_hub/app/providers.dart';
import 'package:finance_hub/domain/entities/category_rule.dart';
import 'package:finance_hub/domain/entities/merchant_rule.dart';
import 'package:finance_hub/domain/services/recategorization_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 全部关键词规则（含被禁用的，由界面自行区分展示）。
final categoryRulesProvider = FutureProvider<List<CategoryRule>>(
  (Ref ref) async => ref.watch(ruleRepositoryProvider).loadCategoryRules(),
);

/// 全部商户记忆。
final merchantRulesProvider = FutureProvider<List<MerchantRule>>(
  (Ref ref) async => ref.watch(ruleRepositoryProvider).loadMerchantRules(),
);

/// 重跑分类服务 —— 依赖当前分类引擎（含最新规则与商户记忆）。
///
/// 修改规则后只要 `ref.invalidate(categorizationEngineProvider)`，
/// 这个 provider 也会跟着重建，重跑用的就是新规则。
final recategorizationServiceProvider =
    FutureProvider<RecategorizationService>((Ref ref) async {
  final engine = await ref.watch(categorizationEngineProvider.future);
  return RecategorizationService(
    repository: ref.watch(transactionRepositoryProvider),
    engine: engine,
  );
});
