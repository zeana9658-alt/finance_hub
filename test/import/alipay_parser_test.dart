import 'package:finance_hub/domain/enums/bill_source.dart';
import 'package:finance_hub/domain/enums/transaction_status.dart';
import 'package:finance_hub/domain/enums/transaction_type.dart';
import 'package:finance_hub/import/decode/text_decoder.dart';
import 'package:finance_hub/import/parsers/alipay_parser.dart';
import 'package:finance_hub/import/table/csv_reader.dart';
import 'package:finance_hub/import/table/raw_table.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/fixture_loader.dart';

void main() {
  final parser = AlipayParser();

  RawTable tableOfBytes(String name) {
    final decoded = TextDecoder.decode(FixtureLoader.bytes(name));
    return CsvReader.read(decoded.text, origin: name);
  }

  group('AlipayParser —— 旧版表头（UTF-8）', () {
    late final result = parser.parse(tableOfBytes('mock_alipay.csv'));

    test('解析条数', () {
      expect(result.totalDataRows, 6);
      expect(result.successCount, 6);
      expect(result.errorCount, 0);
    });

    test('支出', () {
      final first = result.parsed[0].transaction;
      expect(first.source, BillSource.alipay);
      expect(first.transactionType, TransactionType.expense);
      expect(first.amountCents, 880);
      expect(first.merchant, '示例便利店');
      expect(first.description, '饮料');
      expect(first.paymentMethod, '支付宝');
      expect(first.note, '夜宵');
      expect(first.sourceTransactionId, 'TEST-ALI-0001');
    });

    test('收入', () {
      final income = result.parsed[3].transaction;
      expect(income.transactionType, TransactionType.income);
      expect(income.amountCents, 50000);
      expect(income.merchant, '示例公司');
    });

    test('不计收支 → transfer（参考项目在此处会误判为收入）', () {
      final transfer = result.parsed[4].transaction;
      expect(transfer.transactionType, TransactionType.transfer);
      expect(transfer.amountCents, 30000);
      expect(transfer.defaultSelectedInImport, isFalse);
      expect(transfer.signedCents, 0);
    });

    test('交易关闭 → closed，默认不勾选', () {
      final closed = result.parsed[5].transaction;
      expect(closed.status, TransactionStatus.closed);
      expect(closed.defaultSelectedInImport, isFalse);
      // 仍然被解析出来（不静默丢弃），用户可以自己决定
      expect(closed.amountCents, 35900);
    });

    test('资金状态列不会与交易状态混淆', () {
      // 归一化后 '资金状态' 与 '交易状态' 都能命中 status 别名，
      // 但别名顺序保证 '交易状态' 优先
      expect(result.parsed[0].transaction.status, TransactionStatus.success);
    });
  });

  group('AlipayParser —— GBK 与 UTF-8 结果必须完全一致', () {
    test('逐字段比对', () {
      final utf8Result = parser.parse(tableOfBytes('mock_alipay.csv'));
      final gbkResult = parser.parse(tableOfBytes('mock_alipay_gbk.csv'));

      expect(gbkResult.successCount, utf8Result.successCount);
      expect(gbkResult.errorCount, utf8Result.errorCount);
      expect(gbkResult.totalDataRows, utf8Result.totalDataRows);

      for (var i = 0; i < utf8Result.parsed.length; i++) {
        final a = utf8Result.parsed[i].transaction;
        final b = gbkResult.parsed[i].transaction;
        expect(b.merchant, a.merchant, reason: '第 $i 条商户名不一致');
        expect(b.description, a.description, reason: '第 $i 条商品名不一致');
        expect(b.amountCents, a.amountCents, reason: '第 $i 条金额不一致');
        expect(b.transactionTime, a.transactionTime, reason: '第 $i 条时间不一致');
        expect(b.transactionType, a.transactionType);
        expect(b.uniqueKey, a.uniqueKey, reason: '第 $i 条指纹不一致');
      }
    });
  });

  group('AlipayParser —— 新版表头', () {
    late final result = parser.parse(
      CsvReader.read(FixtureLoader.text('mock_alipay_v2.csv'), origin: 'v2'),
    );

    test('解析条数', () {
      expect(result.successCount, 3);
      expect(result.errorCount, 0);
    });

    test('平台原始分类被保留（供分类引擎第二优先级使用）', () {
      final first = result.parsed[0].transaction;
      expect(first.platformCategory, '餐饮美食');
      expect(first.amountCents, 950);
      expect(first.sourceTransactionId, 'TEST-ALI2-0001');
    });

    test('交易订单号被识别为交易单号', () {
      expect(result.parsed[1].transaction.sourceTransactionId, 'TEST-ALI2-0002');
      expect(result.parsed[1].transaction.merchant, '示例网约车');
    });
  });
}
