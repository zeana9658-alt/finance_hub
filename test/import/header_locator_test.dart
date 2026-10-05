import 'package:finance_hub/import/table/header_locator.dart';
import 'package:finance_hub/import/table/header_normalizer.dart';
import 'package:finance_hub/import/table/raw_table.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HeaderNormalizer', () {
    test('全角与半角括号归一', () {
      expect(HeaderNormalizer.normalize('金额(元)'), '金额');
      expect(HeaderNormalizer.normalize('金额（元）'), '金额');
      expect(HeaderNormalizer.normalize('金额 (元)'), '金额');
      expect(HeaderNormalizer.normalize('金额'), '金额');
    });

    test('去标点与货币单位', () {
      expect(HeaderNormalizer.normalize('收/支'), '收支');
      expect(HeaderNormalizer.normalize('人民币金额'), '金额');
      expect(HeaderNormalizer.normalize('交易时间 '), '交易时间');
      expect(HeaderNormalizer.normalize('\uFEFF交易时间'), '交易时间');
    });

    test('不破坏正常列名', () {
      expect(HeaderNormalizer.normalize('交易对方'), '交易对方');
      expect(HeaderNormalizer.normalize('当前状态'), '当前状态');
      expect(HeaderNormalizer.normalize('商品说明'), '商品说明');
    });
  });

  group('HeaderLocator', () {
    test('跳过前导说明文字定位表头', () {
      const table = RawTable(<List<String>>[
        <String>['微信支付账单明细'],
        <String>['微信昵称：[示例用户]'],
        <String>['导出类型：[全部]'],
        <String>['----------------------微信支付账单明细列表--------------------'],
        <String>[
          '交易时间', '交易类型', '交易对方', '商品', '收/支',
          '金额(元)', '支付方式', '当前状态', '交易单号', '商户单号', '备注',
        ],
        <String>[
          '2026-06-12 08:30:00', '商户消费', '示例咖啡', '拿铁', '支出',
          '28.00', '零钱', '支付成功', 'TEST-WX-0001', 'MER-1', '/',
        ],
      ]);

      final header = HeaderLocator.locate(table);
      expect(header, isNotNull);
      expect(header!.rowNumber, 5);
      expect(header.dataStartIndex, 5);
      expect(header.timeIndex, 0);
      expect(header.amountIndex, 5);
      expect(header.merchantIndex, 2);
      expect(header.statusIndex, 7);
      expect(header.externalIdIndex, 8);
    });

    test('支付宝旧版表头（付款时间 / 商品名称 / 交易来源地）', () {
      const table = RawTable(<List<String>>[
        <String>['支付宝交易记录明细查询'],
        <String>['账号：[示例账号]'],
        <String>[
          '交易号', '商家订单号', '交易创建时间', '付款时间', '最近修改时间',
          '交易来源地', '类型', '交易对方', '商品名称', '金额（元）', '收/支',
          '交易状态', '服务费（元）', '成功退款（元）', '备注', '资金状态',
        ],
      ]);

      final header = HeaderLocator.locate(table);
      expect(header, isNotNull);
      expect(header!.rowNumber, 3);
      // 别名优先级：交易创建时间 先于 付款时间
      expect(header.normalizedHeaders[header.timeIndex], '交易创建时间');
      expect(header.normalizedHeaders[header.amountIndex], '金额');
      expect(header.normalizedHeaders[header.merchantIndex], '交易对方');
      expect(header.normalizedHeaders[header.descriptionIndex], '商品名称');
      expect(header.normalizedHeaders[header.paymentMethodIndex], '交易来源地');
      expect(header.normalizedHeaders[header.externalIdIndex], '交易号');
    });

    test('支付宝新版表头（交易分类 / 商品说明 / 交易订单号）', () {
      const table = RawTable(<List<String>>[
        <String>[
          '交易时间', '交易分类', '交易对方', '商品说明', '收/支', '金额',
          '支付方式', '交易状态', '交易订单号', '商家订单号', '备注',
        ],
      ]);

      final header = HeaderLocator.locate(table);
      expect(header, isNotNull);
      expect(header!.categoryIndex, 1);
      expect(header.descriptionIndex, 3);
      expect(header.externalIdIndex, 8);
    });

    test('找不到表头返回 null', () {
      const table = RawTable(<List<String>>[
        <String>['这是一份没有表头的文件'],
        <String>['随便写点什么'],
      ]);
      expect(HeaderLocator.locate(table), isNull);
    });

    test('扫描行数上限 30', () {
      final rows = List<List<String>>.generate(
        40,
        (index) => <String>['无关行 $index'],
      );
      // 第 35 行才是表头 —— 超出扫描上限，应返回 null
      rows[35] = <String>['交易时间', '金额(元)'];
      expect(HeaderLocator.locate(RawTable(rows)), isNull);
    });

    test('findColumn 先精确后包含', () {
      final headers = HeaderNormalizer.normalizeRow(
        <String>['备注', '交易时间', '金额(元)'],
      );
      // 精确匹配优先：'金额' 精确命中下标 2，而不是被 '备注' 之类干扰
      expect(HeaderLocator.findColumn(headers, <String>['金额']), 2);
      expect(HeaderLocator.findColumn(headers, <String>['交易时间']), 1);
      expect(HeaderLocator.findColumn(headers, <String>['不存在的列']), -1);
    });
  });
}
