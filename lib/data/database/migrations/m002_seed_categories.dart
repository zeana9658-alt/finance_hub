import 'dart:convert';

import 'package:finance_hub/data/database/migrations/migration.dart';
import 'package:finance_hub/data/database/seed_data.dart';
import 'package:sqflite/sqflite.dart';

/// v2 —— 写入种子分类与内置关键词规则。
///
/// 分类树来源：[seedCategories]（17 个一级分类，对齐 brief 第 9 条）。
/// 规则来源：[seedRules]（`is_builtin = 1`，用户可禁用但不可删除）。
class M002SeedCategories extends Migration {
  const M002SeedCategories();

  @override
  int get version => 2;

  @override
  String get name => 'seed_categories_and_rules';

  /// 一级分类的 id 索引，键为 `分类名`；二级分类键为 `一级名/二级名`。
  @override
  Future<void> up(DatabaseExecutor db) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final idByPath = <String, int>{};

    for (var i = 0; i < seedCategories.length; i++) {
      final seed = seedCategories[i];

      final topId = await db.insert('categories', <String, Object?>{
        'parent_id': null,
        'level': 1,
        'name': seed.name,
        'kind': seed.kind.code,
        'icon': seed.icon,
        'color': seed.color,
        'sort_order': i,
        'is_system': 1,
        'is_active': 1,
        'created_at': now,
        'updated_at': now,
      });
      idByPath[seed.name] = topId;

      for (var j = 0; j < seed.subcategories.length; j++) {
        final sub = seed.subcategories[j];
        final subId = await db.insert('categories', <String, Object?>{
          'parent_id': topId,
          'level': 2,
          'name': sub.name,
          'kind': seed.kind.code,
          'icon': null,
          'color': seed.color,
          'sort_order': j,
          'is_system': 1,
          'is_active': 1,
          'created_at': now,
          'updated_at': now,
        });
        idByPath['${seed.name}/${sub.name}'] = subId;
      }
    }

    for (final rule in seedRules) {
      final topId = idByPath[rule.targetPath.first];
      if (topId == null) {
        // 种子数据自相矛盾时跳过而不是让整个迁移失败。
        continue;
      }
      final subPath = rule.targetPath.length > 1
          ? '${rule.targetPath[0]}/${rule.targetPath[1]}'
          : null;
      final subId = subPath == null ? null : idByPath[subPath];

      await db.insert('category_rules', <String, Object?>{
        'name': rule.name,
        'enabled': 1,
        'priority': rule.priority,
        'source': 'any',
        'merchant_contains': rule.merchantContains.isEmpty
            ? null
            : jsonEncode(rule.merchantContains),
        'description_contains': rule.descriptionContains.isEmpty
            ? null
            : jsonEncode(rule.descriptionContains),
        'amount_min_cents': null,
        'amount_max_cents': null,
        'direction': rule.direction?.code ?? 'any',
        'match_mode': rule.matchMode.code,
        'target_category_id': topId,
        'target_subcategory_id': subId,
        'hit_count': 0,
        'is_builtin': 1,
        'created_at': now,
        'updated_at': now,
      });
    }
  }
}
