import 'package:finance_hub/domain/entities/category.dart';
import 'package:finance_hub/domain/entities/category_rule.dart';
import 'package:finance_hub/domain/entities/merchant_rule.dart';
import 'package:finance_hub/domain/enums/category_source.dart';
import 'package:finance_hub/domain/services/categorization_engine.dart';
import 'package:finance_hub/domain/services/platform_category_map.dart';

/// 从数据库里读出来的原始数据构建分类引擎。
///
/// 为什么抽成独立函数：provider 与测试必须走**完全相同**的构建路径，
/// 否则会出现「测试通过、线上行为不一致」这种最难查的问题。
///
/// 做两件事：
/// 1. 建立「分类名路径 → id」索引（一级用 `名称`，二级用 `父名/名称`）
/// 2. 把 [platformCategoryMap] 里的**平台分类名**解析成本机分类 id
///    （分类 id 在不同安装实例上不同，所以备份/恢复要按名称重映射）
CategorizationEngine buildCategorizationEngine({
  required List<CategoryRule> rules,
  required List<MerchantRule> merchantRules,
  required List<Category> categories,
}) {
  final byId = <int, Category>{};
  for (final category in categories) {
    final id = category.id;
    if (id != null) {
      byId[id] = category;
    }
  }

  final idByPath = <String, int>{};
  for (final category in categories) {
    final id = category.id;
    if (id == null) {
      continue;
    }
    final parentId = category.parentId;
    if (parentId == null) {
      idByPath[category.name] = id;
      continue;
    }
    final parent = byId[parentId];
    if (parent != null) {
      idByPath['${parent.name}/${category.name}'] = id;
    }
  }

  final platformMap = <String, CategoryAssignment>{};
  for (final entry in platformCategoryMap.entries) {
    final topId = idByPath[entry.value.first];
    if (topId == null) {
      continue;
    }
    final subId =
        entry.value.length > 1 ? idByPath[entry.value.join('/')] : null;
    platformMap[entry.key] = CategoryAssignment(
      source: CategorySource.platform,
      categoryId: topId,
      subcategoryId: subId,
    );
  }

  return CategorizationEngine(
    rules: rules,
    merchantRules: merchantRules,
    platformCategoryMap: platformMap,
  );
}
