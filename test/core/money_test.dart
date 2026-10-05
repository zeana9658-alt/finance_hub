import 'package:finance_hub/core/money/money.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseMoneyToCents —— 绝不因浮点丢分', () {
    test('常见写法', () {
      expect(parseMoneyToCents('38.52'), 3852);
      expect(parseMoneyToCents('38.5'), 3850);
      expect(parseMoneyToCents('38'), 3800);
      expect(parseMoneyToCents('0.07'), 7);
      expect(parseMoneyToCents('0.1'), 10);
      expect(parseMoneyToCents('0'), 0);
    });

    test('浮点陷阱回归：38.52 * 100 == 3851.9999999999995', () {
      // 若实现里用了 double，这里会得到 3851
      expect(parseMoneyToCents('38.52'), isNot(3851));
      expect(parseMoneyToCents('38.52'), 3852);
      expect(parseMoneyToCents('0.29'), 29);
      expect(parseMoneyToCents('1.005'), 100);
    });

    test('带货币符号与千分位', () {
      expect(parseMoneyToCents('¥38'), 3800);
      expect(parseMoneyToCents('￥ 38.5'), 3850);
      expect(parseMoneyToCents(r'$12.34'), 1234);
      expect(parseMoneyToCents('1,234.56'), 123456);
      expect(parseMoneyToCents('1,234,567.89'), 123456789);
      expect(parseMoneyToCents('\u3000 58.00 '), 5800);
    });

    test('负数写法', () {
      expect(parseMoneyToCents('-38.52'), -3852);
      expect(parseMoneyToCents('(38.52)'), -3852);
      expect(parseMoneyToCents('+38.52'), 3852);
    });

    test('超过两位小数截断', () {
      expect(parseMoneyToCents('38.567'), 3856);
      expect(parseMoneyToCents('38.999'), 3899);
    });

    test('无法解析返回 null（调用方须记为错误行）', () {
      expect(parseMoneyToCents(''), isNull);
      expect(parseMoneyToCents('   '), isNull);
      expect(parseMoneyToCents('待确认'), isNull);
      expect(parseMoneyToCents('1.2.3'), isNull);
      expect(parseMoneyToCents('--5'), isNull);
      expect(parseMoneyToCents('abc'), isNull);
      expect(parseMoneyToCents('1,2a3'), isNull);
    });
  });

  group('formatCents', () {
    test('基本格式化', () {
      expect(formatCents(3852), '38.52');
      expect(formatCents(0), '0.00');
      expect(formatCents(5), '0.05');
      expect(formatCents(50), '0.50');
      expect(formatCents(-3852), '-38.52');
    });

    test('千分位', () {
      expect(formatCents(123456), '1,234.56');
      expect(formatCents(123456789), '1,234,567.89');
      expect(formatCents(100000), '1,000.00');
      expect(formatCents(99999), '999.99');
    });

    test('符号选项', () {
      expect(formatCents(3852, withSymbol: true), '\u00A538.52');
      expect(formatCents(3852, showSign: true), '+38.52');
      expect(formatCents(-3852, showSign: true), '-38.52');
    });
  });

  group('Money 值对象', () {
    test('算术', () {
      expect((const Money(3852) + const Money(100)).cents, 3952);
      expect((const Money(3852) - const Money(100)).cents, 3752);
      expect((-const Money(3852)).cents, -3852);
      expect(const Money(-3852).abs().cents, 3852);
      expect((const Money(100) * 3).cents, 300);
    });

    test('相等性与比较', () {
      expect(const Money(100), const Money(100));
      expect(const Money(100).hashCode, const Money(100).hashCode);
      expect(const Money(100).compareTo(const Money(200)), lessThan(0));
      expect(const Money(200).compareTo(const Money(100)), greaterThan(0));
    });

    test('fromYuan 使用 round 而非截断', () {
      expect(Money.fromYuan(38.52).cents, 3852);
      expect(Money.fromYuan(0.29).cents, 29);
    });

    test('toString 走格式化', () {
      expect(const Money(3852).toString(), '38.52');
    });
  });
}
