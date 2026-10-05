import 'package:finance_hub/core/utils/date_range.dart';
import 'package:finance_hub/core/utils/text_utils.dart';
import 'package:finance_hub/domain/entities/normalized_transaction.dart';
import 'package:finance_hub/domain/enums/bill_source.dart';

/// 跨平台疑似重复检测用的探针。
///
/// [baseKey] **刻意不含 source** —— 这样「微信 麦当劳 ¥38」与
/// 「支付宝 麦当劳 ¥38」会撞到同一个 baseKey，从而能被识别为
/// **疑似跨平台重复**（提示用户，但不自动判重）。
class TransactionProbe {
  const TransactionProbe({required this.baseKey, required this.source});

  final String baseKey;
  final BillSource source;

  factory TransactionProbe.of(NormalizedTransaction tx) => TransactionProbe(
        baseKey: baseProbeKeyOf(tx),
        source: tx.source,
      );

  /// 同日 + 同金额 + 同商户（**不含来源**）。
  static String baseProbeKeyOf(NormalizedTransaction tx) =>
      '${dayKey(tx.transactionTime)}|${tx.amountCents}|'
      '${merchantKeyOf(tx.merchant)}';
}

/// 单条交易的判重结论。
class DuplicateVerdict {
  const DuplicateVerdict({
    required this.isDuplicate,
    this.isSuspectedCrossPlatform = false,
    this.reason = '',
  });

  /// 强重复：`unique_key` 命中库中已有记录，或在本批次内重复。
  /// 预览页默认**不勾选**。
  final bool isDuplicate;

  /// 疑似跨平台重复：同日 + 同额 + 同商户，但来源不同。
  ///
  /// 预览页**仍然默认勾选**，只给出黄色提示让用户自己判断
  /// （brief 第 8 条：微信 ¥38 与支付宝 ¥38 可能是两笔不同交易）。
  final bool isSuspectedCrossPlatform;

  final String reason;

  static const DuplicateVerdict ok = DuplicateVerdict(isDuplicate: false);

  @override
  String toString() =>
      'DuplicateVerdict(dup=$isDuplicate, cross=$isSuspectedCrossPlatform, $reason)';
}

/// 一次批量判重的完整结果。
class DuplicateScanResult {
  const DuplicateScanResult(this.verdicts);

  /// 与输入列表**等长且同序**，方便按下标回填到候选列表。
  final List<DuplicateVerdict> verdicts;

  int get duplicateCount =>
      verdicts.where((verdict) => verdict.isDuplicate).length;

  int get suspectedCrossPlatformCount =>
      verdicts.where((verdict) => verdict.isSuspectedCrossPlatform).length;

  int get validCount => verdicts
      .where((verdict) => !verdict.isDuplicate)
      .length;
}

/// 去重检测器 —— 全项目最关键的模块之一（brief 第 8 条）。
///
/// 两级判定：
/// 1. **强重复（阻断）**：`unique_key` 命中 → 默认不勾选
/// 2. **疑似跨平台重复（提示）**：同日同额同商户但来源不同 → 仍默认勾选
///
/// 为什么不用「日期 + 金额 + 商户」做唯一判断：会误杀真实的两笔消费
/// （同一天在同一家便利店买两次同样的东西）。
/// 参考项目的 `FamilyFinanceManager` / `lizhang` 都犯了这个问题。
class DuplicateDetector {
  const DuplicateDetector();

  /// 扫描一批待导入交易。
  ///
  /// [existingUniqueKeys]：库中已有的 `unique_key` 集合。
  /// [existingProbes]：库中**同期**已有交易的探针（用于跨平台提示）。
  ///   只需传入导入时间跨度内的数据，不必全表加载。
  DuplicateScanResult scan(
    List<NormalizedTransaction> incoming, {
    Set<String> existingUniqueKeys = const <String>{},
    List<TransactionProbe> existingProbes = const <TransactionProbe>[],
  }) {
    final verdicts = <DuplicateVerdict>[];
    final seenKeys = <String>{};
    final probeIndex = <String, Set<BillSource>>{};

    for (final probe in existingProbes) {
      probeIndex.putIfAbsent(probe.baseKey, () => <BillSource>{}).add(probe.source);
    }

    for (final tx in incoming) {
      final key = tx.uniqueKey;

      // ── 强重复：库中已有，或本批次内已出现 ──
      final inLibrary = existingUniqueKeys.contains(key);
      final inBatch = seenKeys.contains(key);
      final isDuplicate = inLibrary || inBatch;
      seenKeys.add(key);

      // ── 疑似跨平台重复 ──
      final baseKey = TransactionProbe.baseProbeKeyOf(tx);
      final sources = probeIndex[baseKey];
      final crossPlatform = !isDuplicate &&
          sources != null &&
          sources.any((source) => source != tx.source);
      probeIndex.putIfAbsent(baseKey, () => <BillSource>{}).add(tx.source);

      verdicts.add(
        DuplicateVerdict(
          isDuplicate: isDuplicate,
          isSuspectedCrossPlatform: crossPlatform,
          reason: _reason(
            inLibrary: inLibrary,
            inBatch: inBatch,
            crossPlatform: crossPlatform,
          ),
        ),
      );
    }

    return DuplicateScanResult(verdicts);
  }

  String _reason({
    required bool inLibrary,
    required bool inBatch,
    required bool crossPlatform,
  }) {
    if (inLibrary) {
      return '库中已存在相同交易单号/指纹';
    }
    if (inBatch) {
      return '本次导入的文件内出现重复行';
    }
    if (crossPlatform) {
      return '其他平台存在同日同额同商户的交易，请确认是否为两笔';
    }
    return '';
  }
}
