import 'package:finance_hub/core/utils/text_utils.dart';
import 'package:finance_hub/domain/entities/category_rule.dart';
import 'package:finance_hub/domain/entities/merchant_rule.dart';
import 'package:finance_hub/domain/entities/normalized_transaction.dart';
import 'package:finance_hub/domain/enums/category_source.dart';

/// 一次分类的结果。
class CategoryAssignment {
  const CategoryAssignment({
    required this.source,
    this.categoryId,
    this.subcategoryId,
  });

  /// 命中的优先级来源。
  final CategorySource source;

  final int? categoryId;
  final int? subcategoryId;

  bool get isAssigned => categoryId != null;

  /// 未命中任何规则。
  static const CategoryAssignment unassigned =
      CategoryAssignment(source: CategorySource.fallback);

  @override
  String toString() =>
      'CategoryAssignment(cat=$categoryId, sub=$subcategoryId, ${source.code})';
}

/// 分类引擎 —— 三级优先级的落地（brief 第 10 条）。
///
/// ```
/// 1. 用户手动记忆（merchant_rules）        ← 最高
/// 2. 平台原始分类映射（platform_category）
/// 3. 关键词规则（category_rules，按 priority 排序）
/// 4. （预留）AI 分类
/// 5. 其他 / 未分类
/// ```
///
/// **设计要点**：这是一个**纯函数服务** —— 不依赖数据库、不依赖 Flutter。
/// 规则集由外部注入，因此可以随时用新规则**全量重跑**历史账单
/// （借鉴 `cxy0714/beancount-auto-bookkeeping` 的 `reclassifier.py` 独立阶段设计）。
///
/// 重跑时调用方必须跳过 `categorySource.isUserLocked` 的交易（brief 第 11 条）。
class CategorizationEngine {
  const CategorizationEngine({
    this.rules = const <CategoryRule>[],
    this.merchantRules = const <MerchantRule>[],
    this.platformCategoryMap = const <String, CategoryAssignment>{},
  });

  /// 关键词规则（未排序也可，内部会按 priority 排序）。
  final List<CategoryRule> rules;

  /// 商户记忆。
  final List<MerchantRule> merchantRules;

  /// 平台原始分类 → 分类映射。键为归一化后的平台分类文本。
  final Map<String, CategoryAssignment> platformCategoryMap;

  /// 对单条交易分类。
  CategoryAssignment categorize(NormalizedTransaction tx) {
    return _matchMerchantMemory(tx) ??
        _matchPlatformCategory(tx) ??
        _matchKeywordRule(tx) ??
        CategoryAssignment.unassigned;
  }

  /// 批量分类。
  List<CategoryAssignment> categorizeAll(
    List<NormalizedTransaction> transactions,
  ) =>
      transactions.map(categorize).toList(growable: false);

  // ───────────────────── 第一优先级：商户记忆 ─────────────────────

  CategoryAssignment? _matchMerchantMemory(NormalizedTransaction tx) {
    if (merchantRules.isEmpty) {
      return null;
    }
    final key = merchantKeyOf(tx.merchant);
    if (key.isEmpty) {
      return null;
    }

    MerchantRule? best;
    for (final rule in merchantRules) {
      if (rule.key != key) {
        continue;
      }
      if (rule.source != null && rule.source != tx.source) {
        continue;
      }
      // 来源精确匹配优先于 `any`
      if (best == null) {
        best = rule;
        continue;
      }
      if (rule.source != null && best.source == null) {
        best = rule;
      } else if (rule.confidence > best.confidence) {
        best = rule;
      }
    }

    if (best == null) {
      return null;
    }
    return CategoryAssignment(
      source: CategorySource.merchantMemory,
      categoryId: best.categoryId,
      subcategoryId: best.subcategoryId,
    );
  }

  // ───────────────────── 第二优先级：平台原始分类 ─────────────────────

  CategoryAssignment? _matchPlatformCategory(NormalizedTransaction tx) {
    if (platformCategoryMap.isEmpty) {
      return null;
    }
    final raw = tx.platformCategory.trim();
    if (raw.isEmpty) {
      return null;
    }
    final normalized = _normalizeCategoryText(raw);
    final hit = platformCategoryMap[normalized] ??
        platformCategoryMap[raw] ??
        _looseLookup(normalized);
    if (hit == null) {
      return null;
    }
    return CategoryAssignment(
      source: CategorySource.platform,
      categoryId: hit.categoryId,
      subcategoryId: hit.subcategoryId,
    );
  }

  CategoryAssignment? _looseLookup(String normalized) {
    for (final entry in platformCategoryMap.entries) {
      final key = _normalizeCategoryText(entry.key);
      if (key.isEmpty) {
        continue;
      }
      if (key.contains(normalized) || normalized.contains(key)) {
        return entry.value;
      }
    }
    return null;
  }

  String _normalizeCategoryText(String raw) =>
      raw.replaceAll(RegExp(r'[\s\u3000]'), '').toLowerCase();

  // ───────────────────── 第三优先级：关键词规则 ─────────────────────

  CategoryAssignment? _matchKeywordRule(NormalizedTransaction tx) {
    if (rules.isEmpty) {
      return null;
    }
    final ordered = List<CategoryRule>.of(rules)
      ..sort((a, b) => a.priority.compareTo(b.priority));

    for (final rule in ordered) {
      if (_ruleMatches(rule, tx)) {
        return CategoryAssignment(
          source: CategorySource.keyword,
          categoryId: rule.targetCategoryId,
          subcategoryId: rule.targetSubcategoryId,
        );
      }
    }
    return null;
  }

  bool _ruleMatches(CategoryRule rule, NormalizedTransaction tx) {
    if (!rule.enabled) {
      return false;
    }
    if (rule.source != null && rule.source != tx.source) {
      return false;
    }
    if (rule.direction != null && rule.direction != tx.transactionType) {
      return false;
    }
    if (rule.amountMinCents != null && tx.amountCents < rule.amountMinCents!) {
      return false;
    }
    if (rule.amountMaxCents != null && tx.amountCents > rule.amountMaxCents!) {
      return false;
    }

    final merchantHit = rule.merchantContains.isEmpty
        ? null
        : _anyContains(rule.merchantContains, tx.merchant);
    final descriptionHit = rule.descriptionContains.isEmpty
        ? null
        : _anyContains(rule.descriptionContains, tx.description);

    switch (rule.matchMode) {
      case RuleMatchMode.any:
        return (merchantHit ?? false) || (descriptionHit ?? false);
      case RuleMatchMode.all:
        final hits = <bool>[
          ?merchantHit,
          ?descriptionHit,
        ];
        return hits.isNotEmpty && hits.every((hit) => hit);
      case RuleMatchMode.merchantAndDescription:
        return (merchantHit ?? false) && (descriptionHit ?? false);
    }
  }

  bool _anyContains(List<String> keywords, String text) {
    if (text.isEmpty) {
      return false;
    }
    final lower = text.toLowerCase();
    for (final keyword in keywords) {
      if (keyword.isEmpty) {
        continue;
      }
      if (lower.contains(keyword.toLowerCase())) {
        return true;
      }
    }
    return false;
  }
}
