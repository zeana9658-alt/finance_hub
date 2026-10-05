import 'package:finance_hub/domain/entities/normalized_transaction.dart';
import 'package:finance_hub/domain/enums/bill_source.dart';
import 'package:finance_hub/domain/enums/transaction_type.dart';
import 'package:finance_hub/domain/services/duplicate_detector.dart';
import 'package:finance_hub/domain/services/transaction_fingerprint.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const detector = DuplicateDetector();

  NormalizedTransaction tx({
    BillSource source = BillSource.wechat,
    String? externalId,
    DateTime? time,
    int amountCents = 3800,
    String merchant = '示例餐厅',
    String description = '午餐套餐',
    String paymentMethod = '零钱',
    TransactionType type = TransactionType.expense,
  }) {
    final when = time ?? DateTime(2026, 6, 12, 12, 0, 0);
    return NormalizedTransaction(
      source: source,
      sourceTransactionId: externalId,
      uniqueKey: TransactionFingerprint.compute(
        source: source,
        externalId: externalId,
        transactionTime: when,
        amountCents: amountCents,
        merchant: merchant,
        description: description,
        paymentMethod: paymentMethod,
      ),
      transactionTime: when,
      transactionTimeRaw: '',
      transactionType: type,
      transactionTypeRaw: '',
      amountCents: amountCents,
      merchant: merchant,
      description: description,
      paymentMethod: paymentMethod,
      createdAt: when,
      updatedAt: when,
    );
  }

  group('强重复（阻断）', () {
    test('库中已有相同交易单号', () {
      final incoming = tx(externalId: 'TEST-WX-0001');
      final result = detector.scan(
        <NormalizedTransaction>[incoming],
        existingUniqueKeys: <String>{incoming.uniqueKey},
      );
      expect(result.verdicts.single.isDuplicate, isTrue);
      expect(result.verdicts.single.reason, contains('库中已存在'));
      expect(result.duplicateCount, 1);
      expect(result.validCount, 0);
    });

    test('同一文件内出现重复行（批内判重）', () {
      final a = tx(externalId: 'TEST-WX-0001');
      final b = tx(externalId: 'TEST-WX-0001');
      final result = detector.scan(<NormalizedTransaction>[a, b]);
      expect(result.verdicts[0].isDuplicate, isFalse);
      expect(result.verdicts[1].isDuplicate, isTrue);
      expect(result.verdicts[1].reason, contains('文件内出现重复行'));
    });

    test('无单号时用内容指纹判重', () {
      final a = tx();
      final b = tx();
      expect(a.uniqueKey, b.uniqueKey);
      expect(TransactionFingerprint.isContentBased(a.uniqueKey), isTrue);

      final result = detector.scan(
        <NormalizedTransaction>[b],
        existingUniqueKeys: <String>{a.uniqueKey},
      );
      expect(result.verdicts.single.isDuplicate, isTrue);
    });

    test('内容指纹对金额差异敏感', () {
      final a = tx();
      final b = tx(amountCents: 3801);
      expect(a.uniqueKey, isNot(b.uniqueKey));
    });
  });

  group('跨平台同额同商户 —— 不判重复，仅提示', () {
    test('微信与支付宝各一笔 ¥38 同商户', () {
      final wechatTx = tx(source: BillSource.wechat, amountCents: 3800);
      final alipayTx = tx(source: BillSource.alipay, amountCents: 3800);

      // 指纹必须不同（source 参与哈希）
      expect(wechatTx.uniqueKey, isNot(alipayTx.uniqueKey));

      final result = detector.scan(
        <NormalizedTransaction>[wechatTx, alipayTx],
      );
      expect(result.duplicateCount, 0, reason: '跨平台不得判为重复');
      expect(result.verdicts[0].isSuspectedCrossPlatform, isFalse);
      expect(result.verdicts[1].isSuspectedCrossPlatform, isTrue);
      expect(result.verdicts[1].reason, contains('其他平台'));
      expect(result.suspectedCrossPlatformCount, 1);
    });

    test('与库中已有交易跨平台撞车也能提示', () {
      final existing = tx(source: BillSource.wechat, amountCents: 3800);
      final incoming = tx(source: BillSource.alipay, amountCents: 3800);

      final result = detector.scan(
        <NormalizedTransaction>[incoming],
        existingProbes: <TransactionProbe>[TransactionProbe.of(existing)],
      );
      expect(result.duplicateCount, 0);
      expect(result.verdicts.single.isSuspectedCrossPlatform, isTrue);
    });

    test('同平台同日同额同商户但不同单号 → 完全正常（两笔真实消费）', () {
      final a = tx(externalId: 'TEST-WX-1001', amountCents: 3800);
      final b = tx(externalId: 'TEST-WX-1002', amountCents: 3800);

      final result = detector.scan(<NormalizedTransaction>[a, b]);
      expect(result.duplicateCount, 0);
      expect(result.suspectedCrossPlatformCount, 0);
      expect(result.validCount, 2);
    });

    test('不同日期不提示', () {
      final a = tx(
        source: BillSource.wechat,
        time: DateTime(2026, 6, 12, 12),
        amountCents: 3800,
      );
      final b = tx(
        source: BillSource.alipay,
        time: DateTime(2026, 6, 13, 12),
        amountCents: 3800,
      );
      final result = detector.scan(<NormalizedTransaction>[a, b]);
      expect(result.suspectedCrossPlatformCount, 0);
    });

    test('不同金额不提示', () {
      final a = tx(source: BillSource.wechat, amountCents: 3800);
      final b = tx(source: BillSource.alipay, amountCents: 3801);
      final result = detector.scan(<NormalizedTransaction>[a, b]);
      expect(result.suspectedCrossPlatformCount, 0);
    });
  });

  group('边界', () {
    test('空输入', () {
      final result = detector.scan(<NormalizedTransaction>[]);
      expect(result.verdicts, isEmpty);
      expect(result.duplicateCount, 0);
    });

    test('verdicts 与输入等长且同序', () {
      final list = <NormalizedTransaction>[
        tx(externalId: 'A'),
        tx(externalId: 'B'),
        tx(externalId: 'A'),
      ];
      final result = detector.scan(list);
      expect(result.verdicts.length, list.length);
      expect(result.verdicts[2].isDuplicate, isTrue);
      expect(result.verdicts[0].isDuplicate, isFalse);
      expect(result.verdicts[1].isDuplicate, isFalse);
    });
  });
}
