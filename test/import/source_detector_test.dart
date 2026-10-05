import 'package:finance_hub/domain/enums/bill_source.dart';
import 'package:finance_hub/import/detect/source_detector.dart';
import 'package:finance_hub/import/table/csv_reader.dart';
import 'package:finance_hub/import/table/raw_table.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/fixture_loader.dart';

void main() {
  group('SourceDetector —— 表头特征优先', () {
    test('微信表头', () {
      final table = CsvReader.read(
        FixtureLoader.text('mock_wechat.csv'),
        origin: 'mock_wechat.csv',
      );
      final detection = SourceDetector.detect(table);
      expect(detection.source, BillSource.wechat);
      expect(detection.basis, DetectionBasis.header);
      expect(detection.confidence, greaterThan(0.5));
    });

    test('支付宝表头', () {
      final table = CsvReader.read(
        FixtureLoader.text('mock_alipay.csv'),
        origin: 'mock_alipay.csv',
      );
      final detection = SourceDetector.detect(table);
      expect(detection.source, BillSource.alipay);
      expect(detection.basis, DetectionBasis.header);
    });

    test('表头证据优先于文件名', () {
      // 文件名撒谎：把支付宝账单命名为「微信账单.csv」
      final table = CsvReader.read(
        FixtureLoader.text('mock_alipay.csv'),
        origin: '微信账单.csv',
      );
      final detection = SourceDetector.detect(table);
      expect(detection.source, BillSource.alipay);
      expect(detection.basis, DetectionBasis.header);
    });

    test('无表头特征时退回文件名', () {
      const table = RawTable(
        <List<String>>[
          <String>['交易时间', '金额(元)', '交易对方'],
          <String>['2026-06-01 08:00:00', '10.00', '示例店'],
        ],
        origin: '微信支付账单(202606).csv',
      );
      final detection = SourceDetector.detect(table);
      expect(detection.source, BillSource.wechat);
      expect(detection.basis, DetectionBasis.filename);
      expect(detection.confidence, lessThan(0.8));
    });

    test('完全无法识别 → source 为 null', () {
      const table = RawTable(
        <List<String>>[
          <String>['日期', '数值'],
          <String>['2026-06-01', '10'],
        ],
        origin: 'unknown.csv',
      );
      final detection = SourceDetector.detect(table);
      expect(detection.source, isNull);
      expect(detection.basis, DetectionBasis.unknown);
      expect(detection.isCertain, isFalse);
    });

    test('空表不崩溃', () {
      expect(SourceDetector.detect(RawTable.empty).source, isNull);
    });
  });
}
