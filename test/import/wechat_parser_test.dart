import 'package:finance_hub/domain/enums/bill_source.dart';
import 'package:finance_hub/domain/enums/transaction_status.dart';
import 'package:finance_hub/domain/enums/transaction_type.dart';
import 'package:finance_hub/domain/services/transaction_fingerprint.dart';
import 'package:finance_hub/import/parsers/wechat_parser.dart';
import 'package:finance_hub/import/table/csv_reader.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/fixture_loader.dart';

void main() {
  final parser = WechatParser();

  group('WechatParser —— mock_wechat.csv', () {
    late final result = parser.parse(
      CsvReader.read(FixtureLoader.text('mock_wechat.csv'), origin: 'mock_wechat.csv'),
    );

    test('解析条数与错误数', () {
      expect(result.totalDataRows, 7);
      expect(result.successCount, 7);
      expect(result.errorCount, 0);
      expect(result.headerRowNumber, 6);
    });

    test('支出方向与金额（分为单位）', () {
      final coffee = result.parsed[0].transaction;
      expect(coffee.source, BillSource.wechat);
      expect(coffee.transactionType, TransactionType.expense);
      expect(coffee.amountCents, 2800);
      expect(coffee.merchant, '示例咖啡');
      expect(coffee.description, '拿铁');
      expect(coffee.status, TransactionStatus.success);
      expect(coffee.transactionTime, DateTime(2026, 6, 12, 8, 30));
      expect(coffee.paymentMethod, '零钱');
      expect(coffee.note, '');
    });

    test('收入方向', () {
      final income = result.parsed[2].transaction;
      expect(income.transactionType, TransactionType.income);
      expect(income.amountCents, 10000);
      expect(income.signedCents, 10000);
    });

    test('零钱提现 → transfer，默认不勾选', () {
      final transfer = result.parsed[3].transaction;
      expect(transfer.transactionType, TransactionType.transfer);
      expect(transfer.transactionTypeRaw, '零钱提现');
      expect(transfer.amountCents, 100000);
      expect(transfer.defaultSelectedInImport, isFalse);
      expect(transfer.signedCents, 0);
      // 商户名不应是 '/' 这种脏数据
      expect(transfer.merchant, BillSource.wechat.label);
    });

    test('已全额退款 → refund，且默认勾选', () {
      final refund = result.parsed[4].transaction;
      expect(refund.status, TransactionStatus.refunded);
      expect(refund.transactionType, TransactionType.refund);
      expect(refund.amountCents, 19900);
      expect(refund.defaultSelectedInImport, isTrue);
    });

    test('金额恒为非负，方向由类型表达', () {
      for (final item in result.parsed) {
        expect(item.transaction.amountCents, greaterThanOrEqualTo(0));
      }
    });

    test('交易单号存在时使用 src: 指纹', () {
      final coffee = result.parsed[0].transaction;
      expect(coffee.sourceTransactionId, 'TEST-WX-0001');
      expect(coffee.uniqueKey, 'src:wechat:TEST-WX-0001');
      expect(TransactionFingerprint.isSourceIdBased(coffee.uniqueKey), isTrue);
    });

    test('rawData 保留原始行（本地排查用）', () {
      expect(result.parsed[0].transaction.rawData, contains('示例咖啡'));
    });

    test('分隔行与空行被跳过，不计入数据行', () {
      // 文件末尾的分隔线不应产生错误或数据行
      expect(result.totalDataRows, 7);
      expect(result.errors, isEmpty);
    });
  });
}
