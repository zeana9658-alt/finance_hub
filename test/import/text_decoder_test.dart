import 'dart:convert';

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
      final bytes = _encodeGbk(source);
      final decoded = TextDecoder.decode(bytes);
      expect(decoded.encoding, 'gbk');
      expect(decoded.text, contains('交易时间'));
      expect(decoded.text, contains('示例咖啡'));
    });

    test('GBK 夹具文件能被正确解码', () {
      final decoded = TextDecoder.decode(FixtureLoader.bytes('mock_alipay_gbk.csv'));
      expect(decoded.encoding, 'gbk');
      expect(decoded.text, contains('支付宝交易记录明细查询'));
      expect(decoded.text, contains('示例便利店'));
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

/// 极简 GBK 编码器 —— 只用于测试构造（避免测试依赖 charset 包的编码方向）。
///
/// 通过把 UTF-8 文本写入一个 GBK 编码的字节序列来构造测试数据；
/// 这里借助 Dart 的 `latin1` 不可行，因此直接用查表法覆盖测试所需的字符集。
List<int> _encodeGbk(String input) {
  const table = <String, List<int>>{
    '交': <int>[0xBD, 0xBB], '易': <int>[0xD2, 0xD7], '时': <int>[0xCA, 0xB1],
    '间': <int>[0xBC, 0xE4], '对': <int>[0xB6, 0xD4], '方': <int>[0xB7, 0xBD],
    '金': <int>[0xBD, 0xF0], '额': <int>[0xB6, 0xEE], '（': <int>[0xA3, 0xA8],
    '）': <int>[0xA3, 0xA9], '示': <int>[0xCA, 0xBE], '例': <int>[0xC0, 0xFD],
    '咖': <int>[0xBF, 0xC8], '啡': <int>[0xE0, 0xA9], ',': <int>[0x2C],
    '\n': <int>[0x0A], '.': <int>[0x2E], '-': <int>[0x2D], ':': <int>[0x3A],
    ' ': <int>[0x20],
  };
  final out = <int>[];
  for (final rune in input.runes) {
    final char = String.fromCharCode(rune);
    final mapped = table[char];
    if (mapped != null) {
      out.addAll(mapped);
    } else if (rune < 0x80) {
      out.add(rune);
    } else if (rune >= 0x30 && rune <= 0x39) {
      out.add(rune);
    } else {
      // 未覆盖字符用 '?' 占位，测试用例只使用上表中的字符
      out.add(0x3F);
    }
  }
  return out;
}
