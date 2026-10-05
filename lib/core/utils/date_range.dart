/// 时间区间工具 —— 用于账单筛选（今天 / 本周 / 本月 / 今年 / 自定义）。
///
/// 设计要点（见 docs/DATABASE.md §6）：
/// 月份、日期的**边界计算在 Dart 侧完成**，SQL 只做 `transaction_time BETWEEN ? AND ?`
/// 的范围过滤。这样避免依赖 SQLite 的 `localtime` 修饰符在跨时区下行为不一致。
class DateRange {
  const DateRange(this.start, this.end);

  /// 闭区间起点（含）。
  final DateTime start;

  /// 开区间终点（不含），始终是「下一个自然单位的零点」。
  ///
  /// 用开区间而非闭区间，可以彻底避免「23:59:59.999 漏掉」这类边界 bug。
  final DateTime end;

  Duration get duration => end.difference(start);

  bool contains(DateTime time) =>
      !time.isBefore(start) && time.isBefore(end);

  /// 起止的 epoch 毫秒，供 SQL 使用。
  int get startMillis => start.millisecondsSinceEpoch;
  int get endMillis => end.millisecondsSinceEpoch;

  @override
  bool operator ==(Object other) =>
      other is DateRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'DateRange($start ~ $end)';
}

/// 时间区间工厂。
class DateRanges {
  DateRanges._();

  /// 某一天的 00:00:00 ~ 次日 00:00:00。
  static DateRange day(DateTime date) {
    final start = DateTime(date.year, date.month, date.day);
    return DateRange(start, _addDays(start, 1));
  }

  /// 以 [weekStartsOn] 为一周第一天的整周区间（默认周一）。
  static DateRange week(DateTime date, {int weekStartsOn = DateTime.monday}) {
    final dayStart = DateTime(date.year, date.month, date.day);
    final delta = (dayStart.weekday - weekStartsOn + 7) % 7;
    final start = _addDays(dayStart, -delta);
    return DateRange(start, _addDays(start, 7));
  }

  /// 某个月的完整区间。
  static DateRange month(int year, int month) {
    final start = DateTime(year, month);
    final end = month == 12 ? DateTime(year + 1) : DateTime(year, month + 1);
    return DateRange(start, end);
  }

  /// [date] 所在月份的完整区间。
  static DateRange monthOf(DateTime date) => month(date.year, date.month);

  /// 某年的完整区间。
  static DateRange year(int year) => DateRange(DateTime(year), DateTime(year + 1));

  /// [date] 所在年份的完整区间。
  static DateRange yearOf(DateTime date) => year(date.year);

  /// 自定义区间。传入的日期会被规整到当天零点。
  static DateRange custom(DateTime from, DateTime to) {
    final start = DateTime(from.year, from.month, from.day);
    final endExclusive = _addDays(DateTime(to.year, to.month, to.day), 1);
    return DateRange(start, endExclusive);
  }

  /// 上一个月区间（用于环比）。
  static DateRange previousMonth(DateTime date) {
    final prev = date.month == 1
        ? DateTime(date.year - 1, 12)
        : DateTime(date.year, date.month - 1);
    return month(prev.year, prev.month);
  }

  static DateTime _addDays(DateTime date, int days) =>
      DateTime(date.year, date.month, date.day + days);
}

/// 把月份格式化为 `2026-10` 形式的键，用于 SQL 分组与图表 X 轴。
String monthKey(int year, int month) =>
    '$year-${month.toString().padLeft(2, '0')}';

/// 把日期格式化为 `2026-10-05` 形式的键。
String dayKey(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}'
    '-${date.day.toString().padLeft(2, '0')}';
