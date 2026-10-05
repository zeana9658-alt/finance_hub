import 'package:finance_hub/core/utils/date_range.dart';

/// 预算周期。
enum BudgetPeriod {
  daily('daily', '每日'),
  weekly('weekly', '每周'),
  monthly('monthly', '每月'),
  yearly('yearly', '每年');

  const BudgetPeriod(this.code, this.label);

  final String code;
  final String label;

  static BudgetPeriod fromCode(String? code) {
    if (code == null) {
      return BudgetPeriod.monthly;
    }
    for (final value in BudgetPeriod.values) {
      if (value.code == code) {
        return value;
      }
    }
    return BudgetPeriod.monthly;
  }

  /// 给定日期，算出该周期覆盖的时间区间。
  DateRange rangeOf(DateTime date) {
    switch (this) {
      case BudgetPeriod.daily:
        return DateRanges.day(date);
      case BudgetPeriod.weekly:
        return DateRanges.week(date);
      case BudgetPeriod.monthly:
        return DateRanges.monthOf(date);
      case BudgetPeriod.yearly:
        return DateRanges.yearOf(date);
    }
  }

  @override
  String toString() => label;
}

/// 预算实体。
///
/// `category_id` 为空表示「总预算」（不限分类）。
class Budget {
  const Budget({
    this.id,
    this.categoryId,
    this.subcategoryId,
    required this.amountCents,
    this.period = BudgetPeriod.monthly,
    required this.startDate,
    this.endDate,
    this.rollover = false,
    this.isActive = true,
  });

  final int? id;

  /// 一级分类；`null` 表示总预算。
  final int? categoryId;

  /// 二级分类（可选，用于更细的预算）。
  final int? subcategoryId;

  /// 预算金额（分）。
  final int amountCents;

  final BudgetPeriod period;

  final DateTime startDate;
  final DateTime? endDate;

  /// 是否把上期结余滚入本期。
  final bool rollover;

  final bool isActive;

  Budget copyWith({
    int? id,
    int? categoryId,
    int? subcategoryId,
    int? amountCents,
    BudgetPeriod? period,
    DateTime? startDate,
    DateTime? endDate,
    bool? rollover,
    bool? isActive,
  }) {
    return Budget(
      id: id ?? this.id,
      categoryId: categoryId ?? this.categoryId,
      subcategoryId: subcategoryId ?? this.subcategoryId,
      amountCents: amountCents ?? this.amountCents,
      period: period ?? this.period,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      rollover: rollover ?? this.rollover,
      isActive: isActive ?? this.isActive,
    );
  }

  factory Budget.fromMap(Map<String, Object?> map) {
    return Budget(
      id: map['id'] as int?,
      categoryId: map['category_id'] as int?,
      subcategoryId: map['subcategory_id'] as int?,
      amountCents: map['amount_cents'] as int? ?? 0,
      period: BudgetPeriod.fromCode(map['period'] as String?),
      startDate: DateTime.fromMillisecondsSinceEpoch(
        map['start_date'] as int? ?? 0,
      ),
      endDate: map['end_date'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(map['end_date'] as int),
      rollover: (map['rollover'] as int? ?? 0) == 1,
      isActive: (map['is_active'] as int? ?? 1) == 1,
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
        'id': id,
        'category_id': categoryId,
        'subcategory_id': subcategoryId,
        'amount_cents': amountCents,
        'period': period.code,
        'start_date': startDate.millisecondsSinceEpoch,
        'end_date': endDate?.millisecondsSinceEpoch,
        'rollover': rollover ? 1 : 0,
        'is_active': isActive ? 1 : 0,
      };

  Map<String, Object?> toInsertMap() {
    final map = toMap();
    map.remove('id');
    return map;
  }

  @override
  String toString() =>
      'Budget(#$id, category=$categoryId, $amountCents分/${period.code})';
}

/// 预算执行情况 —— 预算 + 本期已用金额。
class BudgetProgress {
  const BudgetProgress({
    required this.budget,
    required this.usedCents,
    required this.categoryName,
    required this.periodRange,
    this.subcategoryName,
  });

  final Budget budget;

  /// 本期已花（分）。
  final int usedCents;

  /// 分类展示名；总预算时为 `总预算`。
  final String categoryName;

  final String? subcategoryName;

  /// 本期的实际时间区间。
  final DateRange periodRange;

  int get limitCents => budget.amountCents;

  int get remainingCents => budget.amountCents - usedCents;

  /// 使用比例（可 > 1）。
  double get ratio =>
      budget.amountCents == 0 ? 0 : usedCents / budget.amountCents;

  bool get isOver => usedCents > budget.amountCents;

  /// 预警档位：0 正常 / 1 接近上限（≥80%）/ 2 已超出。
  ///
  /// UI 用低饱和琥珀色表达 1、2 档，**不使用刺眼的红色警报**
  /// （brief 第 20 条）。
  int get alertLevel {
    if (isOver) {
      return 2;
    }
    if (ratio >= 0.8) {
      return 1;
    }
    return 0;
  }

  @override
  String toString() =>
      'BudgetProgress($categoryName, $usedCents/${budget.amountCents})';
}
