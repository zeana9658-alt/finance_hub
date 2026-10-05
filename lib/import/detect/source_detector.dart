import 'package:finance_hub/domain/enums/bill_source.dart';
import 'package:finance_hub/import/table/header_locator.dart';
import 'package:finance_hub/import/table/raw_table.dart';

/// 来源识别的依据 —— 记录在 `import_records.detected_by`，便于排查识别准确率。
enum DetectionBasis {
  /// 依据表头特征（最可靠）。
  header,

  /// 依据文件名或前几行文本。
  filename,

  /// 用户手动选择。
  manual,

  /// 无法识别。
  unknown;

  String get code => name;
}

/// 来源识别结果。
class SourceDetection {
  const SourceDetection({
    required this.source,
    required this.basis,
    this.confidence = 1.0,
  });

  /// 识别出的来源。`null` 表示无法自动识别，需要用户手动选择。
  final BillSource? source;

  final DetectionBasis basis;

  /// 置信度 0.0 ~ 1.0。
  final double confidence;

  bool get isCertain => source != null;

  static const SourceDetection unknown = SourceDetection(
    source: null,
    basis: DetectionBasis.unknown,
    confidence: 0,
  );

  @override
  String toString() =>
      'SourceDetection(${source?.code ?? 'unknown'}, ${basis.name}, $confidence)';
}

/// 账单来源自动识别器。
///
/// 优先级（见 docs/IMPORT_FORMATS.md §6）：
/// 1. **表头特征** —— 最可靠。用户可能把支付宝账单重命名成 `微信账单.csv`，
///    所以表头证据必须优先于文件名。
/// 2. 文件名 / 前 8 行文本
/// 3. 无法判定 → 返回 `null`，UI 提示「无法自动识别，请选择账单来源」
class SourceDetector {
  SourceDetector._();

  /// 支付宝独有的表头列（归一化后）。
  static const Set<String> _alipayMarkers = <String>{
    '交易分类',
    '商品说明',
    '交易订单号',
    '资金状态',
    '交易号',
    '商家订单号',
    '最近修改时间',
    '服务费',
    '成功退款',
    '交易来源地',
  };

  /// 微信独有的表头列（归一化后）。
  static const Set<String> _wechatMarkers = <String>{
    '当前状态',
    '交易单号',
    '商户单号',
    '交易类型',
  };

  static const List<String> _alipayTextHints = <String>['支付宝', 'alipay'];
  static const List<String> _wechatTextHints = <String>['微信', 'wechat', 'weixin'];

  /// 识别 [table] 的账单来源。
  static SourceDetection detect(RawTable table) {
    if (table.isEmpty) {
      return SourceDetection.unknown;
    }

    final byHeader = _detectByHeader(table);
    if (byHeader != null) {
      return byHeader;
    }

    final byText = _detectByText('${table.origin} ${table.headText()}');
    if (byText != null) {
      return byText;
    }

    return SourceDetection.unknown;
  }

  /// 表头特征识别。
  static SourceDetection? _detectByHeader(RawTable table) {
    final header = HeaderLocator.locate(table);
    if (header == null) {
      return null;
    }

    final headers = header.normalizedHeaders.toSet();
    final alipayHits = headers.intersection(_alipayMarkers).length;
    final wechatHits = headers.intersection(_wechatMarkers).length;

    if (alipayHits == 0 && wechatHits == 0) {
      return null;
    }

    if (alipayHits > wechatHits) {
      return SourceDetection(
        source: BillSource.alipay,
        basis: DetectionBasis.header,
        confidence: _confidence(alipayHits, wechatHits),
      );
    }
    if (wechatHits > alipayHits) {
      return SourceDetection(
        source: BillSource.wechat,
        basis: DetectionBasis.header,
        confidence: _confidence(wechatHits, alipayHits),
      );
    }

    // 打平：用「商品说明」这类强特征再判一次
    if (headers.contains('商品说明') || headers.contains('交易分类')) {
      return const SourceDetection(
        source: BillSource.alipay,
        basis: DetectionBasis.header,
        confidence: 0.6,
      );
    }
    if (headers.contains('当前状态') || headers.contains('交易单号')) {
      return const SourceDetection(
        source: BillSource.wechat,
        basis: DetectionBasis.header,
        confidence: 0.6,
      );
    }
    return null;
  }

  /// 文件名 / 文本特征识别。
  static SourceDetection? _detectByText(String text) {
    final sample = text.toLowerCase();
    final hasAlipay =
        _alipayTextHints.any((hint) => sample.contains(hint.toLowerCase()));
    final hasWechat =
        _wechatTextHints.any((hint) => sample.contains(hint.toLowerCase()));

    if (hasAlipay && !hasWechat) {
      return const SourceDetection(
        source: BillSource.alipay,
        basis: DetectionBasis.filename,
        confidence: 0.7,
      );
    }
    if (hasWechat && !hasAlipay) {
      return const SourceDetection(
        source: BillSource.wechat,
        basis: DetectionBasis.filename,
        confidence: 0.7,
      );
    }
    return null;
  }

  static double _confidence(int winnerHits, int loserHits) {
    final total = winnerHits + loserHits;
    if (total == 0) {
      return 0;
    }
    final ratio = winnerHits / total;
    // 命中数越多越可信：1 个特征 0.6 起，4 个特征 0.95
    final volumeBonus = (winnerHits / 4).clamp(0.0, 1.0) * 0.35;
    return (0.6 + ratio * 0.05 + volumeBonus).clamp(0.0, 0.99);
  }
}
