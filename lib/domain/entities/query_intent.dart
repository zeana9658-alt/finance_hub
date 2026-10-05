/// 自然语言查询要问的**指标**。
enum QueryMetric {
  totalSpent('total_spent', '总支出'),
  totalIncome('total_income', '总收入'),
  balance('balance', '结余'),
  transactionCount('transaction_count', '交易笔数'),
  maxExpense('max_expense', '最大单笔支出'),
  monthlyPeak('monthly_peak', '支出最高的月份'),
  monthOverMonth('month_over_month', '环比变化'),

  /// 没听懂。
  unsupported('unsupported', '暂不支持');

  const QueryMetric(this.code, this.label);

  final String code;
  final String label;
}

/// 查询的时间范围。
enum QueryScope {
  allTime('全部时间'),
  thisYear('今年'),
  lastYear('去年'),
  thisMonth('本月'),
  lastMonth('上月'),
  specificMonth('指定月份'),
  specificYear('指定年份');

  const QueryScope(this.label);

  final String label;
}

/// 从自然语言里解析出的结构化查询意图。
///
/// **这是 brief 第 22 条的关键设计**：AI（或这里的本地规则）只负责
/// 「理解问题」，真正的数据检索由本地数据库执行。
/// 所以这个类里**没有 SQL**，只有结构化的条件。
class QueryIntent {
  const QueryIntent({
    required this.metric,
    this.scope = QueryScope.allTime,
    this.year,
    this.month,
    this.keyword,
    this.rawQuestion = '',
    this.hint,
  });

  final QueryMetric metric;

  final QueryScope scope;

  /// 指定年份（`scope == specificYear` 或配合月份使用）。
  final int? year;

  /// 指定月份 1–12。
  final int? month;

  /// 分类或商户关键词（如「咖啡」「外卖」「星巴克」）。
  ///
  /// 执行时**先尝试按分类名匹配**，匹配不到再按商户名模糊匹配 ——
  /// 这样「咖啡」能命中「餐饮/咖啡茶饮」这个分类，
  /// 而「星巴克」会落到商户过滤上。
  final String? keyword;

  final String rawQuestion;

  /// 没听懂时给用户的提示。
  final String? hint;

  bool get isUnderstood => metric != QueryMetric.unsupported;

  bool get hasKeyword => keyword != null && keyword!.isNotEmpty;

  QueryIntent copyWith({
    QueryMetric? metric,
    QueryScope? scope,
    int? year,
    int? month,
    String? keyword,
    String? hint,
  }) {
    return QueryIntent(
      metric: metric ?? this.metric,
      scope: scope ?? this.scope,
      year: year ?? this.year,
      month: month ?? this.month,
      keyword: keyword ?? this.keyword,
      rawQuestion: rawQuestion,
      hint: hint ?? this.hint,
    );
  }

  @override
  String toString() =>
      'QueryIntent(${metric.code}, scope=${scope.name}, '
      'year=$year, month=$month, keyword=$keyword)';
}

/// 本地查询的结果。
class QueryOutcome {
  const QueryOutcome({
    required this.intent,
    required this.answer,
    required this.amountCents,
    this.detail,
    this.comparisonCents,
    this.comparisonLabel,
  });

  final QueryIntent intent;

  /// 本地生成的可读答案（离线也能看）。
  final String answer;

  /// 主数值（分）。不适用的指标为 0。
  final int amountCents;

  /// 补充说明（如最大一笔的商户名与日期）。
  final String? detail;

  /// 环比场景下的对比数值。
  final int? comparisonCents;

  /// 对比标签（如「上月」）。
  final String? comparisonLabel;

  @override
  String toString() => 'QueryOutcome($answer)';
}
