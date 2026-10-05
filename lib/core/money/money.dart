/// 金额值对象 —— 全项目**唯一**允许表示金额的类型。
///
/// 内部以「分」为单位的 [int] 存储，彻底避免浮点误差。
///
/// 为什么必须这样：`38.52 * 100` 在 IEEE-754 下等于 `3851.9999999999995`，
/// 截断后变成 `3851` —— 平白少了一分钱。账单金额是精确的十进制数，
/// 必须用整数运算。
///
/// 参见 docs/ARCHITECTURE.md §1 原则 3、docs/DATABASE.md §3。
class Money implements Comparable<Money> {
  const Money(this.cents);

  /// 以「分」为单位的整数金额。
  ///
  /// 允许为负：净额（收入 − 支出）需要负数表达。
  /// 单笔交易的「收入/支出」方向由 `TransactionType` 表达，金额本身恒为正。
  final int cents;

  static const Money zero = Money(0);

  /// 仅用于测试与种子数据的便捷构造。
  ///
  /// 使用 [num.round] 而非截断，避免 `fromYuan(38.52)` 得到 3851。
  /// **生产代码不要用这个**，请用 [parseMoneyToCents] 从字符串解析。
  factory Money.fromYuan(num yuan) => Money((yuan * 100).round());

  bool get isZero => cents == 0;
  bool get isPositive => cents > 0;
  bool get isNegative => cents < 0;

  Money operator +(Money other) => Money(cents + other.cents);
  Money operator -(Money other) => Money(cents - other.cents);
  Money operator -() => Money(-cents);
  Money operator *(int factor) => Money(cents * factor);
  Money abs() => Money(cents.abs());

  @override
  int compareTo(Money other) => cents.compareTo(other.cents);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Money && other.cents == cents);

  @override
  int get hashCode => cents.hashCode;

  @override
  String toString() => formatCents(cents);
}

final RegExp _digitsOnly = RegExp(r'^\d+$');

/// 把账单里的金额字符串解析为「分」。
///
/// 返回 `null` 表示**无法解析**。调用方必须把它记为一条错误行并展示给用户，
/// **不要静默丢弃**（见 docs/IMPORT_FORMATS.md §5.2）。
///
/// 支持的形式：
/// ```text
/// '38.52'    -> 3852
/// '38.5'     -> 3850
/// '38'       -> 3800
/// '0.07'     -> 7
/// '1,234.56' -> 123456
/// '¥38'      -> 3800
/// '￥ 38.5'   -> 3850
/// '-38.52'   -> -3852
/// '(38.52)'  -> -3852   （会计括号负数）
/// '38.567'   -> 3856    （超过两位小数直接截断）
/// ''         -> null
/// '待确认'    -> null
/// ```
int? parseMoneyToCents(String raw) {
  var s = raw
      .replaceAll('\u00A5', '') // ¥
      .replaceAll('\uFFE5', '') // ￥
      .replaceAll(r'$', '')
      .replaceAll(',', '')
      .replaceAll('\u3000', '') // 全角空格
      .replaceAll(' ', '')
      .trim();

  if (s.isEmpty) {
    return null;
  }

  var negative = false;
  if (s.startsWith('-')) {
    negative = true;
    s = s.substring(1);
  } else if (s.startsWith('+')) {
    s = s.substring(1);
  }

  // 会计写法：(38.52) 表示负数
  if (s.length >= 2 && s.startsWith('(') && s.endsWith(')')) {
    negative = !negative;
    s = s.substring(1, s.length - 1);
  }

  if (s.isEmpty) {
    return null;
  }

  final parts = s.split('.');
  if (parts.length > 2) {
    return null;
  }

  final intPart = parts[0].isEmpty ? '0' : parts[0];
  if (!_digitsOnly.hasMatch(intPart)) {
    return null;
  }

  var fracPart = parts.length == 2 ? parts[1] : '';
  if (fracPart.isNotEmpty && !_digitsOnly.hasMatch(fracPart)) {
    return null;
  }
  if (fracPart.length > 2) {
    fracPart = fracPart.substring(0, 2);
  }
  fracPart = fracPart.padRight(2, '0');

  final value = int.parse(intPart) * 100 + int.parse(fracPart);
  return negative ? -value : value;
}

/// 把「分」格式化为展示字符串。
///
/// ```text
/// formatCents(3852)                       -> '38.52'
/// formatCents(5)                          -> '0.05'
/// formatCents(123456789)                  -> '1,234,567.89'
/// formatCents(-3852)                      -> '-38.52'
/// formatCents(3852, withSymbol: true)     -> '¥38.52'
/// formatCents(3852, showSign: true)       -> '+38.52'
/// ```
String formatCents(
  int cents, {
  bool withSymbol = false,
  bool showSign = false,
}) {
  final negative = cents < 0;
  final abs = cents.abs();
  final yuan = abs ~/ 100;
  final fen = abs % 100;

  final buffer = StringBuffer();
  if (negative) {
    buffer.write('-');
  } else if (showSign) {
    buffer.write('+');
  }
  if (withSymbol) {
    buffer.write('\u00A5');
  }
  buffer.write(_groupDigits(yuan));
  buffer.write('.');
  buffer.write(fen.toString().padLeft(2, '0'));
  return buffer.toString();
}

/// 千分位分组：1234567 -> '1,234,567'
String _groupDigits(int value) {
  final s = value.toString();
  if (s.length <= 3) {
    return s;
  }
  final buffer = StringBuffer();
  final firstGroup = s.length % 3;
  if (firstGroup > 0) {
    buffer.write(s.substring(0, firstGroup));
  }
  for (var i = firstGroup; i < s.length; i += 3) {
    if (buffer.isNotEmpty) {
      buffer.write(',');
    }
    buffer.write(s.substring(i, i + 3));
  }
  return buffer.toString();
}
