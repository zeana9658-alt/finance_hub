import 'package:finance_hub/core/money/money.dart';
import 'package:finance_hub/domain/entities/financial_summary.dart';

/// 洞察的重要程度，决定界面用什么颜色。
enum InsightSeverity {
  /// 中性陈述。
  info,

  /// 正面（如"比上月省了"）。
  positive,

  /// 值得注意（如"超预算"）—— 用低饱和琥珀，不用刺眼红。
  attention,
}

/// 一条消费洞察。
class Insight {
  const Insight({
    required this.title,
    required this.body,
    this.severity = InsightSeverity.info,
  });

  final String title;
  final String body;
  final InsightSeverity severity;

  @override
  String toString() => '[$title] $body';
}

/// 本地消费洞察生成器。
///
/// **完全离线**：只用 [FinancialSummary] 里的聚合数字做规则推理，
/// 不需要联网、不需要 API Key。这也是 brief 第 21 条里
/// "AI 分析"的**可降级形态** —— 没配模型时用户照样能得到有价值的结论。
///
/// 接了大模型之后，这些本地结论会作为 `FinancialSummary` 的补充
/// 一起给模型润色，但结论本身仍然是本地算出来的（数字不会被模型改动）。
class InsightGenerator {
  InsightGenerator._();

  /// 夜间时段（21:00–06:00）的桶下标。
  static const Set<int> _nightBuckets = <int>{0, 6};

  static List<Insight> generate(FinancialSummary summary) {
    final insights = <Insight>[];

    if (summary.transactionCount == 0) {
      return const <Insight>[
        Insight(
          title: '这段时间没有记录',
          body: '导入账单或手动记几笔之后，这里会给出消费结构分析。',
        ),
      ];
    }

    _addTopCategory(insights, summary);
    _addConcentration(insights, summary);
    _addTrend(insights, summary);
    _addNightSpending(insights, summary);
    _addWeekendPattern(insights, summary);
    _addBudgetStatus(insights, summary);
    _addBigTicket(insights, summary);

    if (insights.isEmpty) {
      insights.add(
        const Insight(
          title: '消费结构比较均衡',
          body: '没有发现明显的异常集中或突增，继续保持。',
        ),
      );
    }
    return insights;
  }

  // ───────────────────────── 各条规则 ─────────────────────────

  static void _addTopCategory(List<Insight> out, FinancialSummary summary) {
    if (summary.categoryStatistics.isEmpty) {
      return;
    }
    final top = summary.categoryStatistics.first;
    out.add(
      Insight(
        title: '${top.name}是最大支出项',
        body: '${top.name}花了 ${formatCents(top.amountCents, withSymbol: true)}，'
            '占总支出 ${(top.ratio * 100).toStringAsFixed(0)}%，'
            '共 ${top.transactionCount} 笔。',
      ),
    );
  }

  static void _addConcentration(List<Insight> out, FinancialSummary summary) {
    if (summary.categoryStatistics.length < 3) {
      return;
    }
    final top3 = summary.categoryStatistics.take(3).toList(growable: false);
    final ratio = top3.fold<double>(0, (sum, item) => sum + item.ratio);
    if (ratio < 0.6) {
      return;
    }
    out.add(
      Insight(
        title: '支出集中在前 3 类',
        body: '${top3.map((item) => item.name).join('、')}'
            '合计占了 ${(ratio * 100).toStringAsFixed(0)}% 的支出。'
            '想省钱的话，从这三类里挑一类下手效果最明显。',
        severity: InsightSeverity.attention,
      ),
    );
  }

  static void _addTrend(List<Insight> out, FinancialSummary summary) {
    final change = summary.trend.momExpenseChange;
    if (change == null) {
      return;
    }
    final percent = (change.abs() * 100).toStringAsFixed(1);
    if (change > 0.1) {
      out.add(
        Insight(
          title: '支出比上期增加 $percent%',
          body: '本期支出明显高于上一期，可以看看是不是有大额消费或临时开支。',
          severity: InsightSeverity.attention,
        ),
      );
    } else if (change < -0.1) {
      out.add(
        Insight(
          title: '支出比上期减少 $percent%',
          body: '本期比上一期省下了钱，保持这个节奏。',
          severity: InsightSeverity.positive,
        ),
      );
    } else {
      out.add(
        Insight(
          title: '支出与上期基本持平',
          body: '变化幅度 $percent%，消费节奏比较稳定。',
        ),
      );
    }
  }

  static void _addNightSpending(List<Insight> out, FinancialSummary summary) {
    if (summary.timeBucketStatistics.isEmpty) {
      return;
    }
    var nightCents = 0;
    var totalCents = 0;
    for (final bucket in summary.timeBucketStatistics) {
      totalCents += bucket.amountCents;
      if (_nightBuckets.contains(_bucketIndexOf(bucket.bucket))) {
        nightCents += bucket.amountCents;
      }
    }
    if (totalCents == 0) {
      return;
    }
    final ratio = nightCents / totalCents;
    if (ratio >= 0.25) {
      out.add(
        Insight(
          title: '夜间消费占比偏高',
          body: '21:00 之后的消费占了 ${(ratio * 100).toStringAsFixed(0)}%，'
              '金额 ${formatCents(nightCents, withSymbol: true)}。'
              '深夜下单往往更冲动，值得留意。',
          severity: InsightSeverity.attention,
        ),
      );
    }
  }

  static void _addWeekendPattern(List<Insight> out, FinancialSummary summary) {
    if (summary.dailyStatistics.isEmpty) {
      return;
    }
    var weekendCents = 0;
    var weekendDays = 0;
    var weekdayCents = 0;
    var weekdayDays = 0;

    for (final day in summary.dailyStatistics) {
      final parsed = DateTime.tryParse(day.day);
      if (parsed == null) {
        continue;
      }
      final isWeekend = parsed.weekday == DateTime.saturday ||
          parsed.weekday == DateTime.sunday;
      if (isWeekend) {
        weekendCents += day.expenseCents;
        weekendDays++;
      } else {
        weekdayCents += day.expenseCents;
        weekdayDays++;
      }
    }

    if (weekendDays == 0 || weekdayDays == 0) {
      return;
    }
    final weekendAvg = weekendCents / weekendDays;
    final weekdayAvg = weekdayCents / weekdayDays;
    if (weekdayAvg == 0) {
      return;
    }
    final ratio = weekendAvg / weekdayAvg;
    if (ratio >= 1.3) {
      out.add(
        Insight(
          title: '周末花得比工作日多',
          body: '周末日均 ${formatCents(weekendAvg.round(), withSymbol: true)}，'
              '工作日日均 ${formatCents(weekdayAvg.round(), withSymbol: true)}，'
              '高出 ${((ratio - 1) * 100).toStringAsFixed(0)}%。',
        ),
      );
    }
  }

  static void _addBudgetStatus(List<Insight> out, FinancialSummary summary) {
    if (summary.budgetStatus.isEmpty) {
      return;
    }
    final over = summary.budgetStatus
        .where((item) => item.usedCents > item.limitCents)
        .toList(growable: false);
    final near = summary.budgetStatus
        .where(
          (item) =>
              item.usedCents <= item.limitCents &&
              item.limitCents > 0 &&
              item.usedCents / item.limitCents >= 0.8,
        )
        .toList(growable: false);

    if (over.isNotEmpty) {
      out.add(
        Insight(
          title: '${over.length} 项预算已超出',
          body: over
              .map(
                (item) => '${item.category}超了 '
                    '${formatCents(item.usedCents - item.limitCents, withSymbol: true)}',
              )
              .join('；'),
          severity: InsightSeverity.attention,
        ),
      );
    }
    if (near.isNotEmpty) {
      out.add(
        Insight(
          title: '${near.length} 项预算接近上限',
          body: near
              .map(
                (item) => '${item.category}已用 '
                    '${((item.usedCents / item.limitCents) * 100).toStringAsFixed(0)}%',
              )
              .join('；'),
        ),
      );
    }
  }

  static void _addBigTicket(List<Insight> out, FinancialSummary summary) {
    final total = summary.expenseCents;
    if (total == 0 || summary.categoryStatistics.isEmpty) {
      return;
    }
    // 用「最大分类的均值」近似判断是否存在异常大额
    final top = summary.categoryStatistics.first;
    if (top.transactionCount == 0) {
      return;
    }
    final average = top.amountCents / top.transactionCount;
    if (average >= 50000) {
      out.add(
        Insight(
          title: '${top.name}的单笔金额偏高',
          body: '平均每笔 ${formatCents(average.round(), withSymbol: true)}，'
              '如果有可以延后的非必要开支，这里是最值得优化的地方。',
        ),
      );
    }
  }

  /// 从时段标签反推桶下标（标签形如 `21:00–24:00`）。
  static int _bucketIndexOf(String label) {
    for (var i = 0; i < _bucketLabels.length; i++) {
      if (_bucketLabels[i] == label) {
        return i;
      }
    }
    return -1;
  }

  static const List<String> _bucketLabels = <String>[
    '00:00–06:00',
    '06:00–09:00',
    '09:00–12:00',
    '12:00–15:00',
    '15:00–18:00',
    '18:00–21:00',
    '21:00–24:00',
  ];
}
