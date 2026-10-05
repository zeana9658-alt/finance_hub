import 'package:finance_hub/data/database/app_database.dart';
import 'package:finance_hub/domain/entities/normalized_transaction.dart';
import 'package:finance_hub/domain/entities/statistics.dart';

/// 统计查询层 —— 所有聚合**下推到 SQL**，不在 Dart 侧全表遍历。
///
/// 这是支撑 10000+ 条交易仍可用的关键（见 docs/ARCHITECTURE.md §8）。
///
/// 时间边界由调用方（Dart 侧）算好后传入，SQL 只做范围过滤，
/// 避免依赖 SQLite 的 `localtime` 修饰符在跨时区下行为不一致。
class AnalyticsDao {
  AnalyticsDao(this._database);

  final AppDatabase _database;

  static const String _t = 'transactions';

  /// 区间收支汇总。
  Future<PeriodSummary> summary({
    required int fromMillis,
    required int toMillis,
  }) async {
    final db = await _database.open();
    final rows = await db.rawQuery(
      '''
      SELECT
        COALESCE(SUM(CASE WHEN transaction_type = 'income'  THEN amount_cents END), 0) AS income,
        COALESCE(SUM(CASE WHEN transaction_type = 'expense' THEN amount_cents END), 0) AS expense,
        COALESCE(SUM(CASE WHEN transaction_type = 'refund'  THEN amount_cents END), 0) AS refund,
        COUNT(*) AS cnt
      FROM $_t
      WHERE deleted_at IS NULL
        AND status IN ('success','refunded')
        AND transaction_time >= ? AND transaction_time < ?
      ''',
      <Object?>[fromMillis, toMillis],
    );
    if (rows.isEmpty) {
      return PeriodSummary.empty;
    }
    final row = rows.first;
    return PeriodSummary(
      incomeCents: _asInt(row['income']),
      expenseCents: _asInt(row['expense']),
      refundCents: _asInt(row['refund']),
      transactionCount: _asInt(row['cnt']),
    );
  }

  /// 一级分类聚合（消费分类占比 / 下钻第一层）。
  Future<List<CategoryTotal>> categoryTotals({
    required int fromMillis,
    required int toMillis,
    int? parentCategoryId,
  }) async {
    final db = await _database.open();
    final where = StringBuffer('''
      t.deleted_at IS NULL
      AND t.status IN ('success','refunded')
      AND t.transaction_type IN ('expense','refund')
      AND t.transaction_time >= ? AND t.transaction_time < ?
    ''');
    final args = <Object?>[fromMillis, toMillis];

    if (parentCategoryId == null) {
      where.write(' AND t.category_id IS NOT NULL');
    } else {
      where.write(' AND c.parent_id = ?');
      args.add(parentCategoryId);
    }

    final rows = await db.rawQuery(
      '''
      SELECT c.id AS cid, c.name AS cname, c.color AS ccolor,
             SUM(t.amount_cents) AS total, COUNT(*) AS cnt
      FROM $_t t
      JOIN categories c ON c.id = ${parentCategoryId == null ? 't.category_id' : 't.subcategory_id'}
      WHERE $where
      GROUP BY c.id
      ORDER BY total DESC
      ''',
      args,
    );

    return rows
        .map(
          (row) => CategoryTotal(
            categoryId: _asInt(row['cid']),
            name: row['cname'] as String? ?? '未分类',
            color: row['ccolor'] as String?,
            amountCents: _asInt(row['total']),
            transactionCount: _asInt(row['cnt']),
          ),
        )
        .toList(growable: false);
  }

  /// 按天聚合（消费日历）。
  Future<List<DailyTotal>> dailyTotals({
    required int fromMillis,
    required int toMillis,
  }) async {
    final db = await _database.open();
    final rows = await db.rawQuery(
      '''
      SELECT
        date(transaction_time / 1000, 'unixepoch', 'localtime') AS day,
        COALESCE(SUM(CASE WHEN transaction_type = 'income'  THEN amount_cents END), 0) AS income,
        COALESCE(SUM(CASE WHEN transaction_type IN ('expense','refund') THEN amount_cents END), 0) AS expense
      FROM $_t
      WHERE deleted_at IS NULL
        AND status IN ('success','refunded')
        AND transaction_time >= ? AND transaction_time < ?
      GROUP BY day
      ORDER BY day
      ''',
      <Object?>[fromMillis, toMillis],
    );

    final result = <DailyTotal>[];
    for (final row in rows) {
      final dayText = row['day'] as String?;
      if (dayText == null) {
        continue;
      }
      final parts = dayText.split('-');
      if (parts.length != 3) {
        continue;
      }
      result.add(
        DailyTotal(
          day: DateTime(
            int.parse(parts[0]),
            int.parse(parts[1]),
            int.parse(parts[2]),
          ),
          incomeCents: _asInt(row['income']),
          expenseCents: _asInt(row['expense']),
        ),
      );
    }
    return result;
  }

  /// 大额支出 TOP N。
  Future<List<NormalizedTransaction>> topExpenses({
    required int fromMillis,
    required int toMillis,
    int limit = 5,
  }) async {
    final db = await _database.open();
    final rows = await db.query(
      _t,
      where: '''
        deleted_at IS NULL
        AND status IN ('success','refunded')
        AND transaction_type = 'expense'
        AND transaction_time >= ? AND transaction_time < ?
      ''',
      whereArgs: <Object?>[fromMillis, toMillis],
      orderBy: 'amount_cents DESC',
      limit: limit,
    );
    return rows.map(NormalizedTransaction.fromMap).toList(growable: false);
  }

  /// 商户聚合（商户分析）。
  Future<MerchantStat?> merchantStat(String merchant) async {
    final db = await _database.open();
    final rows = await db.rawQuery(
      '''
      SELECT merchant,
             SUM(amount_cents) AS total,
             COUNT(*) AS cnt,
             CAST(AVG(amount_cents) AS INTEGER) AS avg_cents,
             MAX(transaction_time) AS last_at
      FROM $_t
      WHERE deleted_at IS NULL
        AND status IN ('success','refunded')
        AND transaction_type = 'expense'
        AND merchant = ?
      GROUP BY merchant
      ''',
      <Object?>[merchant],
    );
    if (rows.isEmpty) {
      return null;
    }
    final row = rows.first;
    return MerchantStat(
      merchant: row['merchant'] as String? ?? merchant,
      totalCents: _asInt(row['total']),
      transactionCount: _asInt(row['cnt']),
      averageCents: _asInt(row['avg_cents']),
      lastTransactionAt: DateTime.fromMillisecondsSinceEpoch(
        _asInt(row['last_at']),
      ),
    );
  }

  /// 消费时段分布（7 个桶）。
  ///
  /// 分桶在 Dart 侧完成，SQL 只取小时与金额，避免 SQL 里写 7 段 CASE。
  Future<List<TimeBucketTotal>> timeBucketTotals({
    required int fromMillis,
    required int toMillis,
  }) async {
    final db = await _database.open();
    final rows = await db.rawQuery(
      '''
      SELECT CAST(strftime('%H', transaction_time / 1000, 'unixepoch', 'localtime') AS INTEGER) AS hour,
             SUM(amount_cents) AS total,
             COUNT(*) AS cnt
      FROM $_t
      WHERE deleted_at IS NULL
        AND status IN ('success','refunded')
        AND transaction_type IN ('expense','refund')
        AND transaction_time >= ? AND transaction_time < ?
      GROUP BY hour
      ''',
      <Object?>[fromMillis, toMillis],
    );

    final amounts = List<int>.filled(TimeBucketTotal.labels.length, 0);
    final counts = List<int>.filled(TimeBucketTotal.labels.length, 0);

    for (final row in rows) {
      final hour = _asInt(row['hour']);
      if (hour < 0 || hour > 23) {
        continue;
      }
      final bucket = TimeBucketTotal.bucketOfHour(hour);
      amounts[bucket] += _asInt(row['total']);
      counts[bucket] += _asInt(row['cnt']);
    }

    return List<TimeBucketTotal>.generate(
      amounts.length,
      (index) => TimeBucketTotal(
        bucketIndex: index,
        amountCents: amounts[index],
        transactionCount: counts[index],
      ),
    );
  }

  /// 最近交易（首页用）。
  Future<List<NormalizedTransaction>> recent({
    int limit = 8,
    int? beforeMillis,
  }) async {
    final db = await _database.open();
    final rows = await db.query(
      _t,
      where: beforeMillis == null
          ? 'deleted_at IS NULL'
          : 'deleted_at IS NULL AND transaction_time < ?',
      whereArgs: beforeMillis == null ? null : <Object?>[beforeMillis],
      orderBy: 'transaction_time DESC, id DESC',
      limit: limit,
    );
    return rows.map(NormalizedTransaction.fromMap).toList(growable: false);
  }

  /// 交易总数（设置页展示数据规模）。
  Future<int> totalCount() async {
    final db = await _database.open();
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM $_t WHERE deleted_at IS NULL',
    );
    return _asInt(rows.isEmpty ? null : rows.first['c']);
  }

  /// 多条件查询交易明细（账单页）。
  ///
  /// 所有条件都下推到 SQL，不做全表加载后在 Dart 里过滤。
  /// 条件全部可选，未提供即不参与筛选。
  Future<List<NormalizedTransaction>> search({
    String keyword = '',
    String? source,
    String? transactionType,
    int? categoryId,
    int? fromMillis,
    int? toMillis,
    bool sortByAmountDesc = false,
    int limit = 200,
    int offset = 0,
  }) async {
    final db = await _database.open();
    final where = StringBuffer('deleted_at IS NULL');
    final args = <Object?>[];

    if (source != null && source.isNotEmpty) {
      where.write(' AND source = ?');
      args.add(source);
    }
    if (transactionType != null && transactionType.isNotEmpty) {
      where.write(' AND transaction_type = ?');
      args.add(transactionType);
    }
    if (categoryId != null) {
      where.write(' AND (category_id = ? OR subcategory_id = ?)');
      args
        ..add(categoryId)
        ..add(categoryId);
    }
    if (fromMillis != null) {
      where.write(' AND transaction_time >= ?');
      args.add(fromMillis);
    }
    if (toMillis != null) {
      where.write(' AND transaction_time < ?');
      args.add(toMillis);
    }
    if (keyword.trim().isNotEmpty) {
      where.write(' AND (merchant LIKE ? OR description LIKE ? OR note LIKE ?)');
      final like = '%${keyword.trim()}%';
      args
        ..add(like)
        ..add(like)
        ..add(like);
    }

    final rows = await db.query(
      _t,
      where: where.toString(),
      whereArgs: args,
      orderBy: sortByAmountDesc
          ? 'amount_cents DESC, transaction_time DESC'
          : 'transaction_time DESC, id DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map(NormalizedTransaction.fromMap).toList(growable: false);
  }

  /// 按分类聚合的子分类下钻（分类下钻第二层）。
  Future<List<CategoryTotal>> subcategoryTotals({
    required int parentCategoryId,
    required int fromMillis,
    required int toMillis,
  }) =>
      categoryTotals(
        fromMillis: fromMillis,
        toMillis: toMillis,
        parentCategoryId: parentCategoryId,
      );

  /// 最早/最晚交易时间（数据时间跨度）。
  Future<DateTime?> earliestTime() async {
    final db = await _database.open();
    final rows = await db.rawQuery(
      'SELECT MIN(transaction_time) AS t FROM $_t WHERE deleted_at IS NULL',
    );
    final value = rows.isEmpty ? null : rows.first['t'];
    if (value == null) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(_asInt(value));
  }

  static int _asInt(Object? value) {
    if (value == null) {
      return 0;
    }
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value.toString()) ?? 0;
  }
}
