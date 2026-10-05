import 'dart:convert';

import 'package:finance_hub/core/utils/text_utils.dart';
import 'package:finance_hub/data/database/app_database.dart';
import 'package:finance_hub/domain/entities/category_rule.dart';
import 'package:finance_hub/domain/entities/merchant_rule.dart';
import 'package:finance_hub/domain/enums/bill_source.dart';
import 'package:finance_hub/domain/enums/transaction_type.dart';
import 'package:finance_hub/domain/repositories/rule_repository.dart';
import 'package:sqflite/sqflite.dart' as sqflite;

/// [RuleRepository] 的 SQLite 实现。
class RuleRepositoryImpl implements RuleRepository {
  RuleRepositoryImpl(this._database);

  final AppDatabase _database;

  static const String _rules = 'category_rules';
  static const String _merchants = 'merchant_rules';

  // ───────────────────────── 读 ─────────────────────────

  @override
  Future<List<CategoryRule>> loadCategoryRules() async {
    final db = await _database.open();
    final rows = await db.query(_rules, orderBy: 'priority, id');
    return rows.map(_ruleFromMap).toList(growable: false);
  }

  @override
  Future<List<MerchantRule>> loadMerchantRules() async {
    final db = await _database.open();
    final rows = await db.query(_merchants, orderBy: 'applied_count DESC, id');
    return rows.map(_merchantFromMap).toList(growable: false);
  }

  // ───────────────────────── 规则增删改 ─────────────────────────

  @override
  Future<int> createRule(CategoryRule rule) async {
    final db = await _database.open();
    final now = DateTime.now().millisecondsSinceEpoch;
    return db.insert(_rules, <String, Object?>{
      ..._ruleToMap(rule),
      'is_builtin': 0,
      'hit_count': 0,
      'created_at': now,
      'updated_at': now,
    }..remove('id'));
  }

  @override
  Future<void> updateRule(CategoryRule rule) async {
    final id = rule.id;
    if (id == null) {
      return;
    }
    final db = await _database.open();
    await db.update(
      _rules,
      <String, Object?>{
        ..._ruleToMap(rule),
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      }..remove('id'),
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  @override
  Future<void> deleteRule(int id) async {
    final db = await _database.open();
    // 内置规则不允许删除：即使调用方漏了检查，这里也兜一层。
    await db.delete(
      _rules,
      where: 'id = ? AND is_builtin = 0',
      whereArgs: <Object?>[id],
    );
  }

  @override
  Future<void> setRuleEnabled(int id, bool enabled) async {
    final db = await _database.open();
    await db.update(
      _rules,
      <String, Object?>{
        'enabled': enabled ? 1 : 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  @override
  Future<void> bumpRuleHits(List<int> ruleIds) async {
    if (ruleIds.isEmpty) {
      return;
    }
    final db = await _database.open();
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final id in ruleIds) {
        batch.rawUpdate(
          'UPDATE $_rules SET hit_count = hit_count + 1 WHERE id = ?',
          <Object?>[id],
        );
      }
      await batch.commit(noResult: true);
    });
  }

  // ───────────────────────── 商户记忆 ─────────────────────────

  @override
  Future<void> rememberMerchant({
    required String merchant,
    required int categoryId,
    BillSource? source,
    int? subcategoryId,
  }) async {
    final key = merchantKeyOf(merchant);
    if (key.isEmpty) {
      return;
    }
    final db = await _database.open();
    final now = DateTime.now().millisecondsSinceEpoch;

    await db.insert(
      _merchants,
      <String, Object?>{
        'merchant_key': key,
        'merchant_display': merchant.trim(),
        'source': source?.code ?? 'any',
        'category_id': categoryId,
        'subcategory_id': subcategoryId,
        'confidence': 100,
        'applied_count': 0,
        'last_applied_at': now,
        'created_at': now,
        'updated_at': now,
      },
      conflictAlgorithm: sqflite.ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> forgetMerchant(String merchantKey) async {
    final db = await _database.open();
    await db.delete(
      _merchants,
      where: 'merchant_key = ?',
      whereArgs: <Object?>[merchantKey],
    );
  }

  @override
  Future<void> clearMerchantRules() async {
    final db = await _database.open();
    await db.delete(_merchants);
  }

  // ───────────────────────── 映射 ─────────────────────────

  CategoryRule _ruleFromMap(Map<String, Object?> row) {
    return CategoryRule(
      id: row['id'] as int?,
      name: row['name'] as String? ?? '',
      enabled: (row['enabled'] as int? ?? 1) == 1,
      priority: row['priority'] as int? ?? 100,
      source: _sourceOf(row['source'] as String?),
      merchantContains: _stringList(row['merchant_contains']),
      descriptionContains: _stringList(row['description_contains']),
      amountMinCents: row['amount_min_cents'] as int?,
      amountMaxCents: row['amount_max_cents'] as int?,
      direction: _directionOf(row['direction'] as String?),
      matchMode: RuleMatchMode.fromCode(row['match_mode'] as String?),
      targetCategoryId: row['target_category_id'] as int? ?? 0,
      targetSubcategoryId: row['target_subcategory_id'] as int?,
      hitCount: row['hit_count'] as int? ?? 0,
      isBuiltin: (row['is_builtin'] as int? ?? 0) == 1,
    );
  }

  Map<String, Object?> _ruleToMap(CategoryRule rule) {
    return <String, Object?>{
      'id': rule.id,
      'name': rule.name,
      'enabled': rule.enabled ? 1 : 0,
      'priority': rule.priority,
      'source': rule.source?.code ?? 'any',
      'merchant_contains': rule.merchantContains.isEmpty
          ? null
          : jsonEncode(rule.merchantContains),
      'description_contains': rule.descriptionContains.isEmpty
          ? null
          : jsonEncode(rule.descriptionContains),
      'amount_min_cents': rule.amountMinCents,
      'amount_max_cents': rule.amountMaxCents,
      'direction': rule.direction?.code ?? 'any',
      'match_mode': rule.matchMode.code,
      'target_category_id': rule.targetCategoryId,
      'target_subcategory_id': rule.targetSubcategoryId,
    };
  }

  MerchantRule _merchantFromMap(Map<String, Object?> row) {
    return MerchantRule(
      id: row['id'] as int?,
      merchantDisplay: row['merchant_display'] as String? ?? '',
      merchantKey: row['merchant_key'] as String?,
      source: _sourceOf(row['source'] as String?),
      categoryId: row['category_id'] as int? ?? 0,
      subcategoryId: row['subcategory_id'] as int?,
      confidence: row['confidence'] as int? ?? 100,
      appliedCount: row['applied_count'] as int? ?? 0,
      lastAppliedAt: row['last_applied_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(row['last_applied_at'] as int),
    );
  }

  static List<String> _stringList(Object? value) {
    if (value is! String || value.trim().isEmpty) {
      return const <String>[];
    }
    try {
      final decoded = jsonDecode(value);
      if (decoded is List) {
        return decoded
            .map((item) => '$item')
            .where((item) => item.trim().isNotEmpty)
            .toList(growable: false);
      }
    } on FormatException {
      // 兼容用逗号分隔的旧写法
      return value
          .split(',')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList(growable: false);
    }
    return const <String>[];
  }

  static BillSource? _sourceOf(String? code) {
    if (code == null || code == 'any') {
      return null;
    }
    return BillSource.fromCode(code);
  }

  static TransactionType? _directionOf(String? code) {
    if (code == null || code == 'any') {
      return null;
    }
    return TransactionType.fromCode(code);
  }
}
