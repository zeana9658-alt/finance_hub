/// 分类维度的聚合项。
class CategorySummaryItem {
  const CategorySummaryItem({
    required this.name,
    required this.amountCents,
    required this.ratio,
    required this.transactionCount,
  });

  /// **一级分类名**（如「餐饮」）。来自固定的 17 类分类体系，
  /// 不是用户自定义文本，因此不含隐私信息。
  final String name;

  final int amountCents;

  /// 占总支出的比例（0.0 ~ 1.0）。
  final double ratio;

  final int transactionCount;

  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'amount_cents': amountCents,
        'ratio': double.parse(ratio.toStringAsFixed(4)),
        'count': transactionCount,
      };
}

/// 按天的聚合项。
class DailySummaryItem {
  const DailySummaryItem({
    required this.day,
    required this.incomeCents,
    required this.expenseCents,
  });

  final String day;
  final int incomeCents;
  final int expenseCents;

  Map<String, Object?> toJson() => <String, Object?>{
        'day': day,
        'income_cents': incomeCents,
        'expense_cents': expenseCents,
      };
}

/// 消费时段聚合项。
class TimeBucketSummaryItem {
  const TimeBucketSummaryItem({
    required this.bucket,
    required this.amountCents,
    required this.ratio,
  });

  final String bucket;
  final int amountCents;
  final double ratio;

  Map<String, Object?> toJson() => <String, Object?>{
        'bucket': bucket,
        'amount_cents': amountCents,
        'ratio': double.parse(ratio.toStringAsFixed(4)),
      };
}

/// 预算执行摘要。
class BudgetSummaryItem {
  const BudgetSummaryItem({
    required this.category,
    required this.limitCents,
    required this.usedCents,
  });

  final String category;
  final int limitCents;
  final int usedCents;

  Map<String, Object?> toJson() => <String, Object?>{
        'category': category,
        'limit_cents': limitCents,
        'used_cents': usedCents,
      };
}

/// 环比趋势。
class TrendSummary {
  const TrendSummary({this.momExpenseChange});

  /// 支出环比变化率。上月无支出时为 `null`（无法计算）。
  final double? momExpenseChange;

  String get direction {
    final change = momExpenseChange;
    if (change == null || change.abs() < 0.005) {
      return 'flat';
    }
    return change > 0 ? 'up' : 'down';
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'mom_expense_change': momExpenseChange == null
            ? null
            : double.parse(momExpenseChange!.toStringAsFixed(4)),
        'direction': direction,
      };
}

/// **AI 隐私边界载体** —— 全项目唯一允许外发到模型的数据结构。
///
/// 设计依据 `docs/PRIVACY.md` §4：
///
/// **允许包含**（都是聚合数字，或来自固定分类体系的名称）
/// - 收支总额、结余、笔数
/// - 分类占比（分类名来自固定的 17 类体系，不是用户输入的自由文本）
/// - 按天 / 按时段的聚合数字
/// - 环比趋势、预算执行比例
///
/// **绝对禁止包含**
/// - 商户名称（可反推个人行踪与生活习惯）
/// - 订单号 / 交易单号（唯一标识，可关联）
/// - 银行卡号 / 账号
/// - 逐笔交易记录（等于上传全部账单）
/// - 备注 / 地点 / `raw_data`
///
/// 这个类**在类型层面**就不给上述字段留位置 —— 调用方即使想传也传不进来。
/// 这是比"写文档提醒"更强的约束。
class FinancialSummary {
  const FinancialSummary({
    required this.periodLabel,
    required this.incomeCents,
    required this.expenseCents,
    required this.balanceCents,
    required this.transactionCount,
    this.categoryStatistics = const <CategorySummaryItem>[],
    this.dailyStatistics = const <DailySummaryItem>[],
    this.timeBucketStatistics = const <TimeBucketSummaryItem>[],
    this.budgetStatus = const <BudgetSummaryItem>[],
    this.trend = const TrendSummary(),
  });

  /// 期间标签，如 `2026-10`。
  final String periodLabel;

  final int incomeCents;
  final int expenseCents;
  final int balanceCents;
  final int transactionCount;

  final List<CategorySummaryItem> categoryStatistics;
  final List<DailySummaryItem> dailyStatistics;
  final List<TimeBucketSummaryItem> timeBucketStatistics;
  final List<BudgetSummaryItem> budgetStatus;
  final TrendSummary trend;

  /// 序列化成外发 JSON。
  ///
  /// [includeDaily] / [includeTimeBuckets] / [includeCategories] / [includeBudgets]
  /// 让用户在外发前可以逐项取消勾选（见 docs/PRIVACY.md §4.3）。
  Map<String, Object?> toJson({
    bool includeCategories = true,
    bool includeDaily = true,
    bool includeTimeBuckets = true,
    bool includeBudgets = true,
    bool includeTrend = true,
  }) {
    return <String, Object?>{
      'period': periodLabel,
      'income_cents': incomeCents,
      'expense_cents': expenseCents,
      'balance_cents': balanceCents,
      'transaction_count': transactionCount,
      if (includeCategories)
        'category_statistics': categoryStatistics
            .map((item) => item.toJson())
            .toList(growable: false),
      if (includeDaily)
        'daily_statistics': dailyStatistics
            .map((item) => item.toJson())
            .toList(growable: false),
      if (includeTimeBuckets)
        'time_bucket_statistics': timeBucketStatistics
            .map((item) => item.toJson())
            .toList(growable: false),
      if (includeBudgets)
        'budget_status':
            budgetStatus.map((item) => item.toJson()).toList(growable: false),
      if (includeTrend) 'trend': trend.toJson(),
    };
  }

  /// 给用户看的"数据去向预览"文本。
  String toPrettyJson() {
    final json = toJson();
    final buffer = StringBuffer();
    buffer.writeln('{');
    var index = 0;
    for (final entry in json.entries) {
      index++;
      buffer.write('  "${entry.key}": ');
      buffer.write(_format(entry.value, 1));
      if (index < json.length) {
        buffer.write(',');
      }
      buffer.writeln();
    }
    buffer.write('}');
    return buffer.toString();
  }

  static String _format(Object? value, int indent) {
    final pad = '  ' * indent;
    final closePad = '  ' * (indent - 1);
    if (value is Map) {
      if (value.isEmpty) {
        return '{}';
      }
      final parts = value.entries
          .map((e) => '$pad"${e.key}": ${_format(e.value, indent + 1)}')
          .join(',\n');
      return '{\n$parts\n$closePad}';
    }
    if (value is List) {
      if (value.isEmpty) {
        return '[]';
      }
      final parts = value.map((item) => '$pad${_format(item, indent + 1)}').join(',\n');
      return '[\n$parts\n$closePad]';
    }
    if (value is String) {
      return '"$value"';
    }
    return '$value';
  }

  @override
  String toString() =>
      'FinancialSummary($periodLabel, 收入 $incomeCents / 支出 $expenseCents, '
      '$transactionCount 笔)';
}
