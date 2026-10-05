import 'package:finance_hub/core/money/money.dart';

/// 月度/区间收支汇总。
class PeriodSummary {
  const PeriodSummary({
    required this.incomeCents,
    required this.expenseCents,
    required this.refundCents,
    required this.transactionCount,
  });

  /// 收入合计（分）。
  final int incomeCents;

  /// 支出合计（分）。
  final int expenseCents;

  /// 退款合计（分）—— 是支出的冲减项。
  final int refundCents;

  final int transactionCount;

  /// 结余 = 收入 + 退款 − 支出。
  int get balanceCents => incomeCents + refundCents - expenseCents;

  /// 净支出 = 支出 − 退款。
  int get netExpenseCents => expenseCents - refundCents;

  Money get income => Money(incomeCents);
  Money get expense => Money(expenseCents);
  Money get balance => Money(balanceCents);

  bool get isEmpty => transactionCount == 0;

  static const PeriodSummary empty = PeriodSummary(
    incomeCents: 0,
    expenseCents: 0,
    refundCents: 0,
    transactionCount: 0,
  );

  /// 相对上一个区间的支出变化率。上一个区间为 0 时返回 `null`（无法计算）。
  double? expenseChangeRate(PeriodSummary previous) {
    if (previous.expenseCents == 0) {
      return null;
    }
    return (netExpenseCents - previous.netExpenseCents) /
        previous.netExpenseCents;
  }
}

/// 分类聚合结果。
class CategoryTotal {
  const CategoryTotal({
    required this.categoryId,
    required this.name,
    this.color,
    required this.amountCents,
    required this.transactionCount,
  });

  final int categoryId;
  final String name;
  final String? color;
  final int amountCents;
  final int transactionCount;

  Money get amount => Money(amountCents);

  /// 在给定总额中的占比（0.0 ~ 1.0）。总额为 0 时返回 0。
  double ratioOf(int totalCents) =>
      totalCents == 0 ? 0 : amountCents / totalCents;
}

/// 按天的收支汇总（消费日历用）。
class DailyTotal {
  const DailyTotal({
    required this.day,
    required this.incomeCents,
    required this.expenseCents,
  });

  /// 当天零点（本地时间）。
  final DateTime day;

  final int incomeCents;
  final int expenseCents;

  int get netCents => incomeCents - expenseCents;

  /// 当天的消费强度（用于日历热力着色），范围为支出金额。
  int get intensityCents => expenseCents;
}

/// 商户聚合结果（商户分析用）。
class MerchantStat {
  const MerchantStat({
    required this.merchant,
    required this.totalCents,
    required this.transactionCount,
    required this.averageCents,
    required this.lastTransactionAt,
  });

  final String merchant;
  final int totalCents;
  final int transactionCount;
  final int averageCents;
  final DateTime lastTransactionAt;

  Money get total => Money(totalCents);
  Money get average => Money(averageCents);
}

/// 时段聚合结果（消费时间分布用）。
///
/// 分桶固定为 7 段：`00-06 / 06-09 / 09-12 / 12-15 / 15-18 / 18-21 / 21-24`。
class TimeBucketTotal {
  const TimeBucketTotal({
    required this.bucketIndex,
    required this.amountCents,
    required this.transactionCount,
  });

  final int bucketIndex;
  final int amountCents;
  final int transactionCount;

  /// 7 个时段的展示标签。
  static const List<String> labels = <String>[
    '00:00–06:00',
    '06:00–09:00',
    '09:00–12:00',
    '12:00–15:00',
    '15:00–18:00',
    '18:00–21:00',
    '21:00–24:00',
  ];

  String get label => labels[bucketIndex];

  /// 把小时（0–23）映射到桶下标。
  static int bucketOfHour(int hour) {
    if (hour < 6) {
      return 0;
    }
    if (hour < 9) {
      return 1;
    }
    if (hour < 12) {
      return 2;
    }
    if (hour < 15) {
      return 3;
    }
    if (hour < 18) {
      return 4;
    }
    if (hour < 21) {
      return 5;
    }
    return 6;
  }
}
