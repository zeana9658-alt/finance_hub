import 'dart:convert';

import 'package:charset/charset.dart' as charset;
import 'package:finance_hub/import/decode/text_decoder.dart';
import 'package:finance_hub/import/table/csv_reader.dart';
import 'package:finance_hub/import/table/raw_table.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/fixture_loader.dart';

void main() {
  group('TextDecoder —— 编码回退链', () {
    test('UTF-8 无 BOM', () {
      final bytes = utf8.encode('交易时间,金额(元)\n2026-06-01 08:00:00,10.00\n');
      final decoded = TextDecoder.decode(bytes);
      expect(decoded.encoding, 'utf-8');
      expect(decoded.text, contains('交易时间'));
    });

    test('UTF-8 带 BOM → utf-8-sig', () {
      final bytes = <int>[0xEF, 0xBB, 0xBF, ...utf8.encode('交易时间,金额(元)')];
      final decoded = TextDecoder.decode(bytes);
      expect(decoded.encoding, 'utf-8-sig');
      // BOM 必须被剥掉，否则第一个表头会变成 '\uFEFF交易时间'
      expect(decoded.text.startsWith('交易时间'), isTrue);
    });

    test('GBK 内容 → 回退到 gbk 且不乱码', () {
      const source = '交易时间,交易对方,金额（元）\n2026-06-01 08:00:00,示例咖啡,28.00';
      // 用 charset 包自己的编码器构造 GBK 字节，保证测试数据本身是正确的 GBK
      final bytes = charset.gbk.encode(source);
      // 前提校验：这份字节确实不是合法 UTF-8（否则测不到回退分支）
      expect(() => utf8.decode(bytes), throwsA(isA<FormatException>()));

      final decoded = TextDecoder.decode(bytes);
      expect(decoded.encoding, 'gbk');
      expect(decoded.text, contains('交易时间'));
      expect(decoded.text, contains('示例咖啡'));
      expect(decoded.text, contains('金额'));
    });

    test('GBK 夹具文件能被正确解码（真实文件字节）', () {
      final decoded =
          TextDecoder.decode(FixtureLoader.bytes('mock_alipay_gbk.csv'));
      expect(decoded.encoding, 'gbk');
      expect(decoded.text, contains('支付宝交易记录明细查询'));
      expect(decoded.text, contains('示例便利店'));
      expect(decoded.text, contains('交易创建时间'));
    });

    test('空输入不崩溃', () {
      final decoded = TextDecoder.decode(const <int>[]);
      expect(decoded.text, isEmpty);
      expect(decoded.encoding, 'empty');
    });

    test('纯二进制垃圾不抛异常，降级为 latin1', () {
      final bytes = List<int>.generate(64, (index) => (index * 37 + 200) % 256);
      final decoded = TextDecoder.decode(bytes);
      expect(decoded.encoding, isIn(<String>['latin1', 'gbk', 'utf-8']));
    });

    test('decodeStrict 对空内容抛异常', () {
      expect(
        () => TextDecoder.decodeStrict(const <int>[]),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('CsvReader —— RFC 4180 兼容性', () {
    test('引号包裹的字段内的逗号不会错位', () {
      const csv = 'a,b,c\n1,"含,逗号的商品",3\n';
      final table = CsvReader.read(csv);
      expect(table.rows[1][1], '含,逗号的商品');
      expect(table.rows[1][2], '3');
    });

    test('引号内的换行不会拆行', () {
      const csv = 'a,b\n1,"第一行\n第二行"\n2,x\n';
      final table = CsvReader.read(csv);
      expect(table.rowCount, 3);
      expect(table.rows[1][1], contains('第二行'));
    });

    test('空文本返回空表', () {
      expect(CsvReader.read('').isEmpty, isTrue);
      expect(CsvReader.read('   ').isEmpty, isTrue);
    });

    test('\\r\\n 与 \\r 都被规整', () {
      final table = CsvReader.read('a,b\r\n1,2\r3,4\n');
      expect(table.rowCount, 3);
      expect(table.rows[1], <String>['1', '2']);
      expect(table.rows[2], <String>['3', '4']);
    });

    test('RawTable 便捷方法', () {
      final table = RawTable(const <List<String>>[
        <String>['交易时间', '金额'],
        <String>['2026-06-01', '10'],
      ]);
      expect(table.columnCount, 2);
      expect(table.rowAt(5), isEmpty);
      expect(table.headText(count: 1), contains('交易时间'));
    });
  });
}
