import 'package:finance_hub/domain/entities/query_intent.dart';
import 'package:finance_hub/domain/services/intent_parser.dart';
import 'package:flutter_test/flutter_test.dart';

/// 自然语言意图解析的单元测试。
///
/// 用例直接取自 brief 第 22 条里列出的示例问法。
void main() {
  // 固定"今天"，让所有相对时间断言可复现
  final now = DateTime(2026, 10, 5, 14, 30);

  QueryIntent parse(String question) => IntentParser.parse(question, now: now);

  group('brief 示例问法', () {
    test('我今年在咖啡上花了多少钱？', () {
      final intent = parse('我今年在咖啡上花了多少钱？');
      expect(intent.metric, QueryMetric.totalSpent);
      expect(intent.scope, QueryScope.thisYear);
      expect(intent.year, 2026);
      expect(intent.keyword, '咖啡');
    });

    test('我9月份最大的消费是什么？', () {
      final intent = parse('我9月份最大的消费是什么？');
      expect(intent.metric, QueryMetric.maxExpense);
      expect(intent.scope, QueryScope.specificMonth);
      expect(intent.month, 9);
      // 10 月问 9 月 → 指今年
      expect(intent.year, 2026);
      expect(intent.keyword, isNull);
    });

    test('我这个月比上个月多花了多少钱？', () {
      final intent = parse('我这个月比上个月多花了多少钱？');
      expect(intent.metric, QueryMetric.monthOverMonth);
      expect(intent.scope, QueryScope.thisMonth);
    });

    test('今年哪个月花钱最多？', () {
      final intent = parse('今年哪个月花钱最多？');
      expect(intent.metric, QueryMetric.monthlyPeak);
      expect(intent.scope, QueryScope.thisYear);
    });

    test('我一年在外卖上花了多少？', () {
      final intent = parse('我一年在外卖上花了多少？');
      expect(intent.metric, QueryMetric.totalSpent);
      expect(intent.keyword, '外卖');
    });
  });

  group('时间范围识别', () {
    test('去年', () {
      final intent = parse('去年总支出是多少');
      expect(intent.scope, QueryScope.lastYear);
      expect(intent.year, 2025);
    });

    test('上个月', () {
      final intent = parse('上个月花了多少钱');
      expect(intent.scope, QueryScope.lastMonth);
      expect(intent.year, 2026);
      expect(intent.month, 9);
    });

    test('上个月跨年（1 月问上月）', () {
      final intent = IntentParser.parse('上个月花了多少', now: DateTime(2026, 1, 10));
      expect(intent.scope, QueryScope.lastMonth);
      expect(intent.year, 2025);
      expect(intent.month, 12);
    });

    test('本月', () {
      final intent = parse('本月支出');
      expect(intent.scope, QueryScope.thisMonth);
      expect(intent.month, 10);
    });

    test('「2月」在 10 月问 → 指今年 2 月', () {
      final intent = parse('2月花了多少');
      expect(intent.scope, QueryScope.specificMonth);
      expect(intent.year, 2026);
      expect(intent.month, 2);
    });

    test('「12月」在 10 月问 → 指去年 12 月（未来的月份归到去年）', () {
      final intent = parse('12月花了多少');
      expect(intent.scope, QueryScope.specificMonth);
      expect(intent.year, 2025);
      expect(intent.month, 12);
    });

    test('具体年份', () {
      final intent = parse('2024年花了多少');
      expect(intent.scope, QueryScope.specificYear);
      expect(intent.year, 2024);
    });

    test('没提时间 → 全部时间', () {
      final intent = parse('我花了多少钱');
      expect(intent.scope, QueryScope.allTime);
    });
  });

  group('指标识别', () {
    test('收入', () {
      expect(parse('今年收入多少').metric, QueryMetric.totalIncome);
      expect(parse('我赚了多少钱').metric, QueryMetric.totalIncome);
    });

    test('结余', () {
      expect(parse('今年结余多少').metric, QueryMetric.balance);
    });

    test('笔数', () {
      expect(parse('这个月多少笔交易').metric, QueryMetric.transactionCount);
      expect(parse('今年消费了几次').metric, QueryMetric.transactionCount);
    });

    test('最大单笔', () {
      expect(parse('上个月最大的支出是什么').metric, QueryMetric.maxExpense);
      expect(parse('最贵的一笔是多少').metric, QueryMetric.maxExpense);
    });

    test('★ 顺序正确：「比上个月多花了多少」不能被当成普通支出', () {
      final intent = parse('我这个月比上个月多花了多少');
      expect(intent.metric, QueryMetric.monthOverMonth);
    });

    test('★ 顺序正确：「哪个月花钱最多」不能被当成普通支出', () {
      final intent = parse('今年哪个月花钱最多');
      expect(intent.metric, QueryMetric.monthlyPeak);
    });
  });

  group('关键词抽取', () {
    test('在X上', () {
      expect(parse('我在星巴克花了多少钱').keyword, '星巴克');
      expect(parse('今年在餐饮上花了多少').keyword, '餐饮');
    });

    test('X上花', () {
      expect(parse('外卖上花了多少').keyword, '外卖');
    });

    test('花在X上', () {
      expect(parse('我花在交通上多少钱').keyword, '交通');
    });

    test('纯数字不会被当成关键词', () {
      expect(parse('9月份花了多少').keyword, isNull);
    });

    test('停用词被过滤', () {
      expect(parse('我花了多少钱').keyword, isNull);
    });

    test('没有关键词时返回 null', () {
      expect(parse('今年最大的支出是什么').keyword, isNull);
    });

    test('★ 「X最大的支出」里 X 是关键词，但时间词不算', () {
      // 关键词在「最大/最贵」之前，且常常粘着时间范围。
      expect(parse('2026年餐饮最大的支出是什么').keyword, '餐饮');
      expect(parse('上个月外卖最大的支出').keyword, '外卖');
      // 只剩时间词时不能当成分类 —— 否则「我9月份」会被当成商户名。
      expect(parse('我9月份最大的消费是什么？').keyword, isNull);
      expect(parse('最贵的一笔是多少').keyword, isNull);
    });
  });

  group('无法理解', () {
    test('空问题', () {
      final intent = parse('');
      expect(intent.isUnderstood, isFalse);
      expect(intent.hint, isNotNull);
    });

    test('无关问题', () {
      final intent = parse('今天天气怎么样');
      expect(intent.isUnderstood, isFalse);
      expect(intent.hint, IntentParser.exampleHint);
    });

    test('无法理解时 rawQuestion 保留原问法', () {
      final intent = parse('今天天气怎么样');
      expect(intent.rawQuestion, '今天天气怎么样');
    });
  });

  group('QueryIntent 结构', () {
    test('isUnderstood 与 hasKeyword', () {
      final understood = parse('今年在咖啡上花了多少');
      expect(understood.isUnderstood, isTrue);
      expect(understood.hasKeyword, isTrue);

      final unsupported = parse('??');
      expect(unsupported.isUnderstood, isFalse);
      expect(unsupported.hasKeyword, isFalse);
    });
  });
}
