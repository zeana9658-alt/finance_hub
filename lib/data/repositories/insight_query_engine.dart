import 'package:finance_hub/core/money/money.dart';
import 'package:finance_hub/core/utils/date_range.dart';
import 'package:finance_hub/data/repositories/analytics_dao.dart';
import 'package:finance_hub/domain/entities/normalized_transaction.dart';
import 'package:finance_hub/domain/entities/query_intent.dart';
import 'package:finance_hub/domain/services/intent_parser.dart';

/// 自然语言查询的**本地执行器**。
///
/// **架构红线（brief 第 22 条）**：SQL 全部来自这里的**白名单模板**，
/// 由参数化查询拼装，**绝不接受任何外部生成的 SQL 字符串**。
/// 就算将来接了大模型，模型能影响的也只是 [QueryIntent] 里的结构化字段，
/// 而且每个字段都会经过类型与范围校验。
///
/// 另外：本类产出的 [QueryOutcome.answer] **可能包含商户名**（如"最大一笔是
/// 星巴克"），这是给**本地界面**看的。它永远不应该被发送到模型 ——
/// 外发只允许 [FinancialSummary]。
class InsightQueryEngine {
  const InsightQueryEngine(this._dao);

  final AnalyticsDao _dao;

  Future<QueryOutcome> execute(QueryIntent intent, {DateTime? now}) async {
    if (!intent.isUnderstood) {
      return QueryOutcome(
        intent: intent,
        answer: intent.hint ?? IntentParser.exampleHint,
        amountCents: 0,
      );
    }

    final reference = now ?? DateTime.now();
    final range = _rangeOf(intent, reference);
    final label = _rangeLabel(intent, range, reference);

    // 关键词：先当分类找，找不到再当商户模糊匹配
    List<int>? categoryIds;
    String? merchantLike;
    if (intent.hasKeyword) {
      final keyword = intent.keyword!;
      final categoryId = await _dao.findCategoryIdByName(keyword);
      if (categoryId != null) {
        categoryIds = await _dao.categoryWithChildren(categoryId);
      } else {
        merchantLike = keyword;
      }
    }

    final scopeText = merchantLike == null
        ? (intent.hasKeyword ? '在「${intent.keyword}」上' : '')
        : '在「$merchantLike」';

    switch (intent.metric) {
      case QueryMetric.totalSpent:
        return _totalSpent(intent, range, label, scopeText, categoryIds, merchantLike);

      case QueryMetric.totalIncome:
        return _totalIncome(intent, range, label, categoryIds, merchantLike);

      case QueryMetric.balance:
        return _balance(intent, range, label, categoryIds, merchantLike);

      case QueryMetric.transactionCount:
        return _count(intent, range, label, scopeText, categoryIds, merchantLike);

      case QueryMetric.maxExpense:
        return _maxExpense(intent, range, label, categoryIds, merchantLike);

      case QueryMetric.monthlyPeak:
        return _monthlyPeak(intent, range, label, categoryIds, merchantLike);

      case QueryMetric.monthOverMonth:
        return _monthOverMonth(intent, range, label, reference, categoryIds, merchantLike);

      case QueryMetric.unsupported:
        return QueryOutcome(
          intent: intent,
          answer: intent.hint ?? IntentParser.exampleHint,
          amountCents: 0,
        );
    }
  }

  // ───────────────────────── 各指标 ─────────────────────────

  Future<QueryOutcome> _totalSpent(
    QueryIntent intent,
    DateRange range,
    String label,
    String scopeText,
    List<int>? categoryIds,
    String? merchantLike,
  ) async {
    final summary = await _dao.summaryFiltered(
      fromMillis: range.startMillis,
      toMillis: range.endMillis,
      categoryIds: categoryIds,
      merchantLike: merchantLike,
    );
    final net = summary.netExpenseCents;
    return QueryOutcome(
      intent: intent,
      amountCents: net,
      answer: net == 0
          ? '$label$scopeText没有支出记录'
          : '$label$scopeText共支出 ${formatCents(net, withSymbol: true)}，'
              '${summary.transactionCount} 笔',
    );
  }

  Future<QueryOutcome> _totalIncome(
    QueryIntent intent,
    DateRange range,
    String label,
    List<int>? categoryIds,
    String? merchantLike,
  ) async {
    final summary = await _dao.summaryFiltered(
      fromMillis: range.startMillis,
      toMillis: range.endMillis,
      categoryIds: categoryIds,
      merchantLike: merchantLike,
    );
    return QueryOutcome(
      intent: intent,
      amountCents: summary.incomeCents,
      answer: summary.incomeCents == 0
          ? '$label没有收入记录'
          : '$label共收入 ${formatCents(summary.incomeCents, withSymbol: true)}，'
              '${summary.transactionCount} 笔交易',
    );
  }

  Future<QueryOutcome> _balance(
    QueryIntent intent,
    DateRange range,
    String label,
    List<int>? categoryIds,
    String? merchantLike,
  ) async {
    final summary = await _dao.summaryFiltered(
      fromMillis: range.startMillis,
      toMillis: range.endMillis,
      categoryIds: categoryIds,
      merchantLike: merchantLike,
    );
    final balance = summary.balanceCents;
    return QueryOutcome(
      intent: intent,
      amountCents: balance,
      answer: '$label结余 ${formatCents(balance, withSymbol: true)}'
          '（收入 ${formatCents(summary.incomeCents)}，'
          '支出 ${formatCents(summary.netExpenseCents)}）',
    );
  }

  Future<QueryOutcome> _count(
    QueryIntent intent,
    DateRange range,
    String label,
    String scopeText,
    List<int>? categoryIds,
    String? merchantLike,
  ) async {
    final summary = await _dao.summaryFiltered(
      fromMillis: range.startMillis,
      toMillis: range.endMillis,
      categoryIds: categoryIds,
      merchantLike: merchantLike,
    );
    return QueryOutcome(
      intent: intent,
      amountCents: 0,
      answer: '$label$scopeText共 ${summary.transactionCount} 笔交易',
    );
  }

  Future<QueryOutcome> _maxExpense(
    QueryIntent intent,
    DateRange range,
    String label,
    List<int>? categoryIds,
    String? merchantLike,
  ) async {
    final rows = await _dao.topExpensesFiltered(
      fromMillis: range.startMillis,
      toMillis: range.endMillis,
      categoryIds: categoryIds,
      merchantLike: merchantLike,
      limit: 1,
    );
    if (rows.isEmpty) {
      return QueryOutcome(
        intent: intent,
        amountCents: 0,
        answer: '$label没有支出记录',
      );
    }
    final top = rows.first;
    return QueryOutcome(
      intent: intent,
      amountCents: top.amountCents,
      detail: _describe(top),
      answer: '$label最大的一笔支出是 ${formatCents(top.amountCents, withSymbol: true)}'
          '（${_describe(top)}）',
    );
  }

  Future<QueryOutcome> _monthlyPeak(
    QueryIntent intent,
    DateRange range,
    String label,
    List<int>? categoryIds,
    String? merchantLike,
  ) async {
    // 这个指标需要"逐月对比"，用带过滤的原始数据在 Dart 侧按月聚合
    final rows = await _dao.topExpensesFiltered(
      fromMillis: range.startMillis,
      toMillis: range.endMillis,
      categoryIds: categoryIds,
      merchantLike: merchantLike,
      limit: 100000,
    );
    if (rows.isEmpty) {
      return QueryOutcome(
        intent: intent,
        amountCents: 0,
        answer: '$label没有支出记录',
      );
    }

    final byMonth = <String, int>{};
    for (final row in rows) {
      final key = monthKey(row.transactionTime.year, row.transactionTime.month);
      byMonth[key] = (byMonth[key] ?? 0) + row.amountCents;
    }

    final entries = byMonth.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top = entries.first;
    final parts = top.key.split('-');
    final monthLabel = '${parts[0]}年${int.parse(parts[1])}月';

    return QueryOutcome(
      intent: intent,
      amountCents: top.value,
      detail: monthLabel,
      answer: '$label花钱最多的月份是 $monthLabel，'
          '支出 ${formatCents(top.value, withSymbol: true)}'
          '${entries.length > 1 ? '（第二多的是 ${_monthLabelOf(entries[1].key)}，${formatCents(entries[1].value)}）' : ''}',
    );
  }

  Future<QueryOutcome> _monthOverMonth(
    QueryIntent intent,
    DateRange range,
    String label,
    DateTime reference,
    List<int>? categoryIds,
    String? merchantLike,
  ) async {
    final previous = _previousRange(intent, range, reference);
    final currentSummary = await _dao.summaryFiltered(
      fromMillis: range.startMillis,
      toMillis: range.endMillis,
      categoryIds: categoryIds,
      merchantLike: merchantLike,
    );
    final previousSummary = await _dao.summaryFiltered(
      fromMillis: previous.startMillis,
      toMillis: previous.endMillis,
      categoryIds: categoryIds,
      merchantLike: merchantLike,
    );

    final current = currentSummary.netExpenseCents;
    final before = previousSummary.netExpenseCents;
    final diff = current - before;

    if (before == 0) {
      return QueryOutcome(
        intent: intent,
        amountCents: diff,
        comparisonCents: before,
        comparisonLabel: '上一期',
        answer: '$label支出 ${formatCents(current, withSymbol: true)}；'
            '上一期没有支出记录，无法计算环比',
      );
    }

    final rate = diff / before;
    final direction = diff > 0 ? '多' : '少';
    return QueryOutcome(
      intent: intent,
      amountCents: diff.abs(),
      comparisonCents: before,
      comparisonLabel: '上一期',
      answer: '$label支出 ${formatCents(current, withSymbol: true)}，'
          '比上一期$direction ${formatCents(diff.abs(), withSymbol: true)}'
          '（${(rate.abs() * 100).toStringAsFixed(1)}%）',
    );
  }

  // ───────────────────────── 区间计算 ─────────────────────────

  DateRange _rangeOf(QueryIntent intent, DateTime reference) {
    switch (intent.scope) {
      case QueryScope.allTime:
        return DateRange(DateTime(2000), DateTime(reference.year + 1));
      case QueryScope.thisYear:
        return DateRanges.year(intent.year ?? reference.year);
      case QueryScope.lastYear:
        return DateRanges.year(intent.year ?? reference.year - 1);
      case QueryScope.thisMonth:
        return DateRanges.month(
          intent.year ?? reference.year,
          intent.month ?? reference.month,
        );
      case QueryScope.lastMonth:
        final prev = reference.month == 1
            ? DateTime(reference.year - 1, 12)
            : DateTime(reference.year, reference.month - 1);
        return DateRanges.month(
          intent.year ?? prev.year,
          intent.month ?? prev.month,
        );
      case QueryScope.specificMonth:
        return DateRanges.month(
          intent.year ?? reference.year,
          intent.month ?? reference.month,
        );
      case QueryScope.specificYear:
        return DateRanges.year(intent.year ?? reference.year);
    }
  }

  /// 环比用的「上一期」：月范围取上个月，年范围取上一年，其余取等长前一段。
  DateRange _previousRange(QueryIntent intent, DateRange range, DateTime reference) {
    switch (intent.scope) {
      case QueryScope.thisMonth:
      case QueryScope.lastMonth:
      case QueryScope.specificMonth:
        final start = range.start;
        final prevMonth = start.month == 1
            ? DateTime(start.year - 1, 12)
            : DateTime(start.year, start.month - 1);
        return DateRanges.month(prevMonth.year, prevMonth.month);
      case QueryScope.thisYear:
      case QueryScope.lastYear:
      case QueryScope.specificYear:
        return DateRanges.year(range.start.year - 1);
      case QueryScope.allTime:
        // 全部时间没有"上一期"，退化为上一段等长区间
        final span = range.duration;
        return DateRange(range.start.subtract(span), range.start);
    }
  }

  String _rangeLabel(QueryIntent intent, DateRange range, DateTime reference) {
    switch (intent.scope) {
      case QueryScope.allTime:
        return '全部时间';
      case QueryScope.thisYear:
        return '${range.start.year}年';
      case QueryScope.lastYear:
        return '${range.start.year}年';
      case QueryScope.specificYear:
        return '${range.start.year}年';
      case QueryScope.thisMonth:
      case QueryScope.lastMonth:
      case QueryScope.specificMonth:
        return '${range.start.year}年${range.start.month}月';
    }
  }

  String _describe(NormalizedTransaction tx) {
    final merchant = tx.merchant.isEmpty ? '未知商户' : tx.merchant;
    return '$merchant，${dayKey(tx.transactionTime)}';
  }

  String _monthLabelOf(String key) {
    final parts = key.split('-');
    if (parts.length != 2) {
      return key;
    }
    return '${parts[0]}年${int.parse(parts[1])}月';
  }
}
