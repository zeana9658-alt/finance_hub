import 'package:finance_hub/domain/entities/query_intent.dart';

/// 自然语言问题的本地意图解析器。
///
/// **设计依据 brief 第 22 条**：AI 负责"理解问题"，真正的数据查询
/// 必须由本地数据库完成。这个解析器就是"理解"这一步的**本地实现** ——
/// 用规则而不是模型，好处是：
/// - 完全离线可用，不需要 API Key
/// - 行为确定、可单元测试
/// - 不会把问题里的隐私信息发出去
///
/// 未来接了大模型之后，可以让模型处理这里解析失败的问法，
/// 但**解析结果仍然只是 [QueryIntent]，SQL 依旧由本地白名单模板生成**。
class IntentParser {
  IntentParser._();

  /// 无法理解时的示例提示。
  static const String exampleHint =
      '没听懂这个问题。可以试试：\n'
      '· 我今年在餐饮上花了多少钱\n'
      '· 上个月最大的支出是什么\n'
      '· 今年哪个月花钱最多\n'
      '· 这个月比上个月多花了多少';

  static QueryIntent parse(String question, {DateTime? now}) {
    final text = question.trim();
    if (text.isEmpty) {
      return const QueryIntent(
        metric: QueryMetric.unsupported,
        hint: '请输入一个问题',
      );
    }

    final reference = now ?? DateTime.now();
    final metric = _detectMetric(text);
    if (metric == null) {
      return QueryIntent(
        metric: QueryMetric.unsupported,
        rawQuestion: text,
        hint: exampleHint,
      );
    }

    final scope = _detectScope(text, reference);

    return QueryIntent(
      metric: metric,
      scope: scope.scope,
      year: scope.year,
      month: scope.month,
      keyword: _detectKeyword(text),
      rawQuestion: text,
    );
  }

  // ───────────────────────── 指标 ─────────────────────────

  static QueryMetric? _detectMetric(String text) {
    // 顺序很重要：越具体的指标越先判断。
    // 例如「这个月比上个月多花了多少」里也有「花了」，
    // 必须先命中环比，否则会被当成普通的"花了多少"。
    if (_hasAny(text, const <String>['环比', '对比', '比上个月', '比上月', '比上月多', '比上月少']) ||
        (text.contains('比') && _hasAny(text, const <String>['多花', '少花', '多支出', '少支出']))) {
      return QueryMetric.monthOverMonth;
    }

    if (_hasAny(text, const <String>['哪个月', '哪一月', '哪个的月']) ||
        (text.contains('月份') && _hasAny(text, const <String>['最多', '最高', '最贵']))) {
      return QueryMetric.monthlyPeak;
    }

    if (_hasAny(text, const <String>['最大', '最贵', '最高', '最贵的一笔', '单笔最大'])) {
      return QueryMetric.maxExpense;
    }

    if (_hasAny(text, const <String>[
      '多少笔',
      '几笔',
      '多少单',
      '几单',
      '多少次',
      // 「消费了几次」「买了几次」—— 口语里「次」比「笔」更常见。
      // 少了这一条会被后面的 totalSpent 用「消费」抢走。
      '几次',
      '几回',
      '多少回',
      '交易次数',
      '笔数',
    ])) {
      return QueryMetric.transactionCount;
    }

    if (_hasAny(text, const <String>['收入', '赚了', '进账', '到账', '挣了'])) {
      return QueryMetric.totalIncome;
    }

    if (_hasAny(text, const <String>['结余', '剩下', '剩多少', '攒了', '存了'])) {
      return QueryMetric.balance;
    }

    if (_hasAny(text, const <String>[
      '花了',
      '花费',
      // 「我花在交通上多少钱」「用在吃饭上多少」—— 这两个词不含「花了」，
      // 少了它们整句会被判成 unsupported，连关键词都抽不出来。
      '花在',
      '用在',
      '花到',
      '支出',
      '用了',
      '消费',
      '花销',
      '开销',
    ])) {
      return QueryMetric.totalSpent;
    }

    return null;
  }

  // ───────────────────────── 时间范围 ─────────────────────────

  static _ScopeResult _detectScope(String text, DateTime reference) {
    if (text.contains('去年') || text.contains('上一年')) {
      return _ScopeResult(QueryScope.lastYear, year: reference.year - 1);
    }
    if (text.contains('今年') || text.contains('本年') || text.contains('这年')) {
      return _ScopeResult(QueryScope.thisYear, year: reference.year);
    }
    // 注意顺序：必须先判「这个月」再判「上个月」。
    // 「我这个月比上个月多花了多少」里两个词都出现，
    // 若先判「上个月」会把这个问题的范围错误地定成上月。
    if (text.contains('这个月') ||
        text.contains('本月') ||
        text.contains('这月') ||
        text.contains('当月')) {
      return _ScopeResult(
        QueryScope.thisMonth,
        year: reference.year,
        month: reference.month,
      );
    }
    if (text.contains('上个月') || text.contains('上月')) {
      final prev = reference.month == 1
          ? DateTime(reference.year - 1, 12)
          : DateTime(reference.year, reference.month - 1);
      return _ScopeResult(
        QueryScope.lastMonth,
        year: prev.year,
        month: prev.month,
      );
    }

    final monthMatch = RegExp(r'(\d{1,2})\s*月').firstMatch(text);
    if (monthMatch != null) {
      final month = int.tryParse(monthMatch.group(1)!);
      if (month != null && month >= 1 && month <= 12) {
        // 「9月」在 10 月说 → 指今年；在 2 月说 → 指去年 9 月
        final year = month > reference.month ? reference.year - 1 : reference.year;
        return _ScopeResult(
          QueryScope.specificMonth,
          year: year,
          month: month,
        );
      }
    }

    final yearMatch = RegExp(r'(\d{4})\s*年').firstMatch(text);
    if (yearMatch != null) {
      final year = int.tryParse(yearMatch.group(1)!);
      if (year != null) {
        return _ScopeResult(QueryScope.specificYear, year: year);
      }
    }

    return const _ScopeResult(QueryScope.allTime);
  }

  // ───────────────────────── 关键词 ─────────────────────────

  static final List<RegExp> _keywordPatterns = <RegExp>[
    // 「在X上花了…」
    RegExp(r'在(.{1,12}?)上'),
    // 「我在X花了…」——注意「上」不是必需的，口语里经常省略
    RegExp(r'在(.{1,12}?)(?:花|用|消费|支出|买)'),
    // 「花在X上」「用在X上」
    RegExp(r'(?:花在|用在|花到)(.{1,12}?)(?:上|的|了|里)?[，,。？?\s]*$'),
    // 「X上花了…」
    RegExp(r'(.{1,12}?)上(?:花|用|消费|支出)'),
    // 「…的X花了…」
    RegExp(r'的(.{1,12}?)(?:花了|花费|支出|消费)'),
    // 「X最大的支出」「X最贵的一笔」—— 关键词在「最大/最贵」之前，
    // 注意必须放在上面几条之后：「今年最大的支出」在这里会捕到「今年」，
    // 由 _stripLeadingTime 去掉后判空，才不会把时间词当成分类。
    RegExp(r'(.{1,12}?)(?:最大|最贵|最高|单笔最大)'),
  ];

  /// 关键词前面可能粘着人称与时间范围（「我9月份餐饮」「上个月外卖」），
  /// 剥掉它们，否则「今年最大的支出」会把「今年」当成一个分类名，
  /// 「我9月份最大的消费」会把「我9月份」当成一个商户名。
  static final RegExp _leadingTimePrefix = RegExp(
    r'^(?:我|我们|咱|俺|本人|自己)?'
    r'(?:\d{4}\s*年|\d{1,2}\s*月份?|今年|去年|本年|这年|'
    r'这个月|本月|这月|当月|上个月|上月|今天|昨天|本周|上周)+',
  );

  /// 停用词：这些不是分类/商户名，抽到就丢弃。
  static const Set<String> _stopWords = <String>{
    '我',
    '钱',
    '这',
    '那',
    '它',
    '今年',
    '去年',
    '本月',
    '上月',
    '这个月',
    '上个月',
    '多少',
    '什么',
    '一共',
    '总共',
    '大概',
    '一共花',
  };

  static String? _detectKeyword(String text) {
    for (final pattern in _keywordPatterns) {
      final match = pattern.firstMatch(text);
      if (match == null) {
        continue;
      }
      var keyword = match.group(1)?.trim() ?? '';
      keyword = keyword.replaceAll(RegExp(r'[，,。？?！!\s]'), '');
      keyword = keyword.replaceFirst(_leadingTimePrefix, '').trim();
      if (keyword.isEmpty || _stopWords.contains(keyword)) {
        continue;
      }
      // 纯数字（如「9月」）不是分类关键词
      if (RegExp(r'^\d+$').hasMatch(keyword)) {
        continue;
      }
      return keyword;
    }
    return null;
  }

  static bool _hasAny(String text, List<String> keywords) =>
      keywords.any(text.contains);
}

/// `_detectScope` 的返回：范围 + 解析出的年/月。
class _ScopeResult {
  const _ScopeResult(this.scope, {this.year, this.month});

  final QueryScope scope;
  final int? year;
  final int? month;
}
