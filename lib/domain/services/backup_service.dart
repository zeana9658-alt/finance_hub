import 'dart:convert';

import 'package:finance_hub/core/errors/app_error.dart';

/// 备份文件格式版本。恢复时用它判断兼容性。
const int backupFormatVersion = 1;

/// 备份存储接口（由 data 层实现）。
///
/// 把 SQLite 细节挡在 domain 之外，`BackupService` 才能在无数据库的情况下
/// 用内存实现做单元测试。
abstract class BackupStore {
  /// 读取整张表。`exclude` 用于剔除敏感列（如 `raw_data`）。
  Future<List<Map<String, Object?>>> selectAll(
    String table, {
    Set<String> exclude = const <String>{},
  });

  Future<Map<String, String>> readSettings();

  Future<void> writeSettings(Map<String, String> values);

  /// 当前未删除的交易数。
  Future<int> countActiveTransactions();

  /// 软删除全部交易（「覆盖」恢复模式用）。
  Future<int> softDeleteAllTransactions();

  /// 批量插入，冲突时忽略。返回实际新增数。
  Future<int> insertRowsIgnore(
    String table,
    List<Map<String, Object?>> rows,
  );

  /// 插入分类规则，**按 name 去重**（同名规则已存在则跳过）。
  ///
  /// `category_rules` 表上没有 name 唯一索引，所以不能靠 `INSERT OR IGNORE`
  /// 去重 —— 否则重复恢复会产生同名规则副本。
  Future<int> insertRulesSkippingExistingNames(
    List<Map<String, Object?>> rows,
  );

  /// 插入单行，返回新 id。
  Future<int> insertRow(String table, Map<String, Object?> row);

  /// 新增或更新预算（按 category_id + period 唯一）。
  Future<void> upsertBudget(Map<String, Object?> row);

  /// 按名称查找分类 id（恢复时重映射用）。
  Future<int?> findCategoryId({required String name, int? parentId});

  /// 全部分类的 (id, name, parent_id) 三元组。
  Future<List<Map<String, Object?>>> selectCategoryIndex();
}

/// 恢复模式。
enum RestoreMode {
  /// 合并：跳过重复交易，保留现有数据（**默认**，安全）。
  merge('merge', '合并（跳过重复，保留现有数据）'),

  /// 覆盖：先软删除全部现有交易，再写入备份（危险）。
  overwrite('overwrite', '覆盖（清空现有交易后写入）');

  const RestoreMode(this.code, this.label);

  final String code;
  final String label;
}

/// 备份包 —— 备份文件的内存表示。
class BackupBundle {
  const BackupBundle({
    required this.exportedAt,
    required this.transactions,
    required this.categories,
    required this.categoryRules,
    required this.merchantRules,
    required this.budgets,
    required this.settings,
    this.version = backupFormatVersion,
    this.appVersion = '0.1.1',
    this.includeRawData = false,
  });

  final int version;
  final DateTime exportedAt;
  final String appVersion;

  /// 是否包含 `raw_data`（原始账单行）。默认不含（见 docs/PRIVACY.md §6）。
  final bool includeRawData;

  final List<Map<String, Object?>> transactions;
  final List<Map<String, Object?>> categories;
  final List<Map<String, Object?>> categoryRules;
  final List<Map<String, Object?>> merchantRules;
  final List<Map<String, Object?>> budgets;
  final Map<String, String> settings;

  Map<String, Object?> toJson() => <String, Object?>{
        'format': 'finance_hub_backup',
        'version': version,
        'app_version': appVersion,
        'exported_at': exportedAt.toIso8601String(),
        'include_raw_data': includeRawData,
        'counts': <String, int>{
          'transactions': transactions.length,
          'categories': categories.length,
          'category_rules': categoryRules.length,
          'merchant_rules': merchantRules.length,
          'budgets': budgets.length,
        },
        'transactions': transactions,
        'categories': categories,
        'category_rules': categoryRules,
        'merchant_rules': merchantRules,
        'budgets': budgets,
        'settings': settings,
      };

  String toJsonString({bool pretty = true}) {
    final json = toJson();
    return pretty
        ? const JsonEncoder.withIndent('  ').convert(json)
        : jsonEncode(json);
  }

  factory BackupBundle.fromJson(Map<String, Object?> json) {
    final format = json['format'] as String?;
    if (format != 'finance_hub_backup') {
      throw const BackupFormatException('这不是聚账的备份文件');
    }
    final version = _int(json['version']) ?? 0;
    if (version <= 0) {
      throw const BackupFormatException('备份文件缺少版本号');
    }
    if (version > backupFormatVersion) {
      throw BackupFormatException(
        '备份文件版本过新',
        detail: '文件版本 v$version，当前应用只支持到 v$backupFormatVersion',
      );
    }

    final exportedAtText = json['exported_at'] as String?;
    final exportedAt =
        exportedAtText == null ? null : DateTime.tryParse(exportedAtText);
    if (exportedAt == null) {
      throw const BackupFormatException('备份文件缺少导出时间');
    }

    return BackupBundle(
      version: version,
      exportedAt: exportedAt,
      appVersion: json['app_version'] as String? ?? '未知',
      includeRawData: json['include_raw_data'] == true,
      transactions: _rows(json['transactions']),
      categories: _rows(json['categories']),
      categoryRules: _rows(json['category_rules']),
      merchantRules: _rows(json['merchant_rules']),
      budgets: _rows(json['budgets']),
      settings: _stringMap(json['settings']),
    );
  }

  static List<Map<String, Object?>> _rows(Object? value) {
    if (value is! List) {
      return const <Map<String, Object?>>[];
    }
    return value
        .whereType<Map<Object?, Object?>>()
        .map(
          (row) => row.map(
            (key, item) => MapEntry(key.toString(), item),
          ),
        )
        .toList(growable: false);
  }

  static Map<String, String> _stringMap(Object? value) {
    if (value is! Map) {
      return const <String, String>{};
    }
    return value.map((key, item) => MapEntry(key.toString(), '$item'));
  }

  static int? _int(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse('$value');
  }
}

/// 恢复前的预览（brief 第 23 条：恢复前必须预览 + 确认）。
class BackupPreview {
  const BackupPreview({
    required this.bundle,
    required this.currentTransactionCount,
  });

  final BackupBundle bundle;

  /// 当前库里已有的交易数，用于让用户判断合并/覆盖的影响。
  final int currentTransactionCount;

  int get transactionCount => bundle.transactions.length;
  int get categoryCount => bundle.categories.length;
  int get ruleCount => bundle.categoryRules.length;
  int get merchantRuleCount => bundle.merchantRules.length;
  int get budgetCount => bundle.budgets.length;
  DateTime get exportedAt => bundle.exportedAt;
  bool get includesRawData => bundle.includeRawData;
  String get appVersion => bundle.appVersion;
}

/// 恢复结果。
class RestoreResult {
  const RestoreResult({
    required this.insertedTransactions,
    required this.skippedTransactions,
    required this.restoredBudgets,
    required this.softDeletedTransactions,
  });

  final int insertedTransactions;
  final int skippedTransactions;
  final int restoredBudgets;
  final int softDeletedTransactions;

  @override
  String toString() =>
      'RestoreResult(新增 $insertedTransactions, 跳过 $skippedTransactions, '
      '预算 $restoredBudgets, 软删 $softDeletedTransactions)';
}

/// 备份文件格式错误。
class BackupFormatException extends AppException {
  const BackupFormatException(super.message, {super.detail});
}

/// 备份服务 —— 导出 / 解析 / 预览 / 恢复。
///
/// 隐私约束（docs/PRIVACY.md §6）：
/// - `raw_data` **默认不导出**，需要用户显式勾选「包含原始数据（不推荐）」
/// - 银行卡号只存掩码，因此备份里也不会有完整卡号
class BackupService {
  const BackupService(this._store);

  final BackupStore _store;

  /// 需要排除的敏感列。
  static const Set<String> _sensitiveColumns = <String>{'raw_data'};

  /// 组装备份包。
  Future<BackupBundle> buildBundle({bool includeRawData = false}) async {
    final transactions = await _store.selectAll(
      'transactions',
      exclude: includeRawData ? const <String>{} : _sensitiveColumns,
    );

    return BackupBundle(
      exportedAt: DateTime.now(),
      includeRawData: includeRawData,
      transactions: transactions,
      categories: await _store.selectAll('categories'),
      categoryRules: await _store.selectAll('category_rules'),
      merchantRules: await _store.selectAll('merchant_rules'),
      budgets: await _store.selectAll('budgets'),
      settings: await _store.readSettings(),
    );
  }

  /// 导出为 JSON 字符串。
  Future<String> exportJson({bool includeRawData = false}) async {
    final bundle = await buildBundle(includeRawData: includeRawData);
    return bundle.toJsonString();
  }

  /// 导出交易明细为 CSV。
  ///
  /// 只导出交易（不含分类/规则/预算），用于 Excel 里进一步分析。
  Future<String> exportCsv() async {
    final rows = await _store.selectAll('transactions');
    final buffer = StringBuffer();
    buffer.writeln(
      '交易时间,来源,收支类型,金额(元),商户,商品说明,支付方式,状态,备注,交易单号',
    );

    for (final row in rows) {
      final millis = BackupBundle._int(row['transaction_time']) ?? 0;
      final time = DateTime.fromMillisecondsSinceEpoch(millis);
      final amountCents = BackupBundle._int(row['amount_cents']) ?? 0;
      final typeCode = '${row['transaction_type'] ?? ''}';
      final amount = (amountCents / 100).toStringAsFixed(2);
      final sign = typeCode == 'expense' ? '-' : '';

      buffer.writeln(
        <String>[
          _csvCell(_formatDateTime(time)),
          _csvCell('${row['source'] ?? ''}'),
          _csvCell(_typeLabel(typeCode)),
          _csvCell('$sign$amount'),
          _csvCell('${row['merchant'] ?? ''}'),
          _csvCell('${row['description'] ?? ''}'),
          _csvCell('${row['payment_method'] ?? ''}'),
          _csvCell('${row['status'] ?? ''}'),
          _csvCell('${row['note'] ?? ''}'),
          _csvCell('${row['source_transaction_id'] ?? ''}'),
        ].join(','),
      );
    }
    return buffer.toString();
  }

  /// 解析备份 JSON。
  BackupBundle parseJson(String content) {
    final Object? decoded;
    try {
      decoded = jsonDecode(content);
    } on FormatException catch (error) {
      throw BackupFormatException('备份文件不是合法 JSON', detail: '$error');
    }
    if (decoded is! Map<Object?, Object?>) {
      throw const BackupFormatException('备份文件结构不正确');
    }
    return BackupBundle.fromJson(
      decoded.map((key, value) => MapEntry(key.toString(), value)),
    );
  }

  /// 生成恢复预览。
  Future<BackupPreview> preview(BackupBundle bundle) async {
    final current = await _store.countActiveTransactions();
    return BackupPreview(
      bundle: bundle,
      currentTransactionCount: current,
    );
  }

  /// 执行恢复。
  ///
  /// 分类 id 重映射：备份里的 `category_id` 是本机旧 id，
  /// 恢复时按 **(名称, 父名称)** 匹配到当前库的 id，避免 id 错位导致分类错乱。
  Future<RestoreResult> restore(
    BackupBundle bundle, {
    required RestoreMode mode,
  }) async {
    var softDeleted = 0;
    if (mode == RestoreMode.overwrite) {
      softDeleted = await _store.softDeleteAllTransactions();
    }

    // ── 1. 补齐缺失的分类（按名称匹配）──
    final categoryIdMap = await _remapCategoryIds(bundle);

    // ── 2. 写交易 ──
    //
    // ⚠️ 必须去掉备份里的 `id`：那是**旧库**的主键，直接插入会撞本机主键
    // 而被 `INSERT OR IGNORE` 静默跳过（表现为「恢复后一条都没进来」）。
    // 交易的身份由 `unique_key` 决定，不是 id。
    final transactionRows = <Map<String, Object?>>[];
    for (final row in bundle.transactions) {
      final copy = Map<String, Object?>.of(row)
        ..remove('id')
        ..remove('deleted_at');
      copy['category_id'] = _remapId(copy['category_id'], categoryIdMap);
      copy['subcategory_id'] =
          _remapId(copy['subcategory_id'], categoryIdMap);
      transactionRows.add(copy);
    }
    final inserted =
        await _store.insertRowsIgnore('transactions', transactionRows);

    // ── 3. 写分类规则（按 name 去重，表上没有 name 唯一索引）──
    await _store.insertRulesSkippingExistingNames(bundle.categoryRules);

    // ── 4. 写商户记忆（同样去掉旧主键，靠 UNIQUE(merchant_key, source) 去重）──
    final merchantRows = bundle.merchantRules
        .map((row) => Map<String, Object?>.of(row)..remove('id'))
        .toList(growable: false);
    await _store.insertRowsIgnore('merchant_rules', merchantRows);

    // ── 5. 写预算 ──
    var budgetCount = 0;
    for (final row in bundle.budgets) {
      final copy = Map<String, Object?>.of(row);
      copy['category_id'] = _remapId(copy['category_id'], categoryIdMap);
      copy['subcategory_id'] =
          _remapId(copy['subcategory_id'], categoryIdMap);
      copy.remove('id');
      await _store.upsertBudget(copy);
      budgetCount++;
    }

    // ── 6. 写设置 ──
    if (bundle.settings.isNotEmpty) {
      await _store.writeSettings(bundle.settings);
    }

    return RestoreResult(
      insertedTransactions: inserted,
      skippedTransactions: transactionRows.length - inserted,
      restoredBudgets: budgetCount,
      softDeletedTransactions: softDeleted,
    );
  }

  /// 建立「备份旧 id → 当前库 id」的映射。
  ///
  /// 匹配键是 `(name, parentName)`：分类名 + 父分类名。
  /// 找不到的分类会被补建到当前库里。
  Future<Map<int, int>> _remapCategoryIds(BackupBundle bundle) async {
    final localIndex = await _store.selectCategoryIndex();
    final localByName = <String, int>{};
    final localById = <int, Map<String, Object?>>{};
    for (final row in localIndex) {
      final id = BackupBundle._int(row['id']);
      if (id == null) {
        continue;
      }
      localById[id] = row;
      localByName[_categoryKey(row['name'], row['parent_id'], localById)] = id;
    }

    final backupById = <int, Map<String, Object?>>{};
    for (final row in bundle.categories) {
      final id = BackupBundle._int(row['id']);
      if (id != null) {
        backupById[id] = row;
      }
    }

    final map = <int, int>{};
    for (final row in bundle.categories) {
      final oldId = BackupBundle._int(row['id']);
      final name = '${row['name'] ?? ''}';
      if (oldId == null || name.isEmpty) {
        continue;
      }
      final key = _categoryKey(row['name'], row['parent_id'], backupById);

      final existing = localByName[key];
      if (existing != null) {
        map[oldId] = existing;
        continue;
      }

      // 补建：先把父分类映射好
      final oldParentId = BackupBundle._int(row['parent_id']);
      int? newParentId;
      if (oldParentId != null) {
        newParentId = map[oldParentId];
        if (newParentId == null) {
          final parentRow = backupById[oldParentId];
          if (parentRow != null) {
            newParentId = await _store.findCategoryId(
              name: '${parentRow['name'] ?? ''}',
            );
            if (newParentId != null) {
              map[oldParentId] = newParentId;
            }
          }
        }
      }

      final newId = await _store.insertRow('categories', <String, Object?>{
        'parent_id': newParentId,
        'level': BackupBundle._int(row['level']) ?? 1,
        'name': name,
        'kind': '${row['kind'] ?? 'expense'}',
        'icon': row['icon'],
        'color': row['color'],
        'sort_order': BackupBundle._int(row['sort_order']) ?? 0,
        'is_system': 0,
        'is_active': 1,
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });
      map[oldId] = newId;
      localByName[key] = newId;
    }
    return map;
  }

  /// 分类匹配键：一级用 `name`，二级用 `parentName/name`。
  String _categoryKey(
    Object? name,
    Object? parentId,
    Map<int, Map<String, Object?>> byId,
  ) {
    final n = '${name ?? ''}';
    final pid = BackupBundle._int(parentId);
    if (pid == null) {
      return n;
    }
    final parent = byId[pid];
    final parentName = '${parent?['name'] ?? ''}';
    return parentName.isEmpty ? n : '$parentName/$n';
  }

  Object? _remapId(Object? oldId, Map<int, int> map) {
    final id = BackupBundle._int(oldId);
    if (id == null) {
      return null;
    }
    return map[id] ?? id;
  }

  String _formatDateTime(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
  }

  String _typeLabel(String code) {
    switch (code) {
      case 'income':
        return '收入';
      case 'expense':
        return '支出';
      case 'refund':
        return '退款';
      case 'transfer':
        return '转账';
      default:
        return code;
    }
  }

  /// CSV 字段转义（RFC 4180：含逗号/引号/换行时用双引号包裹）。
  String _csvCell(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }
}
