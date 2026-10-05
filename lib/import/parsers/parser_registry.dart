import 'package:finance_hub/domain/enums/bill_source.dart';
import 'package:finance_hub/import/parsers/alipay_parser.dart';
import 'package:finance_hub/import/parsers/bill_parser.dart';
import 'package:finance_hub/import/parsers/wechat_parser.dart';

/// 解析器注册表。
///
/// 新增来源（京东 / 银行卡 / 信用卡）只需在这里加一行，
/// 导入流水线（`ImportPipeline`）零改动。
class ParserRegistry {
  ParserRegistry._();

  static final List<BillParser> _parsers = <BillParser>[
    WechatParser(),
    AlipayParser(),
    // 预留：
    // JdParser(),
    // BankParser(),
    // CreditCardParser(),
  ];

  /// 所有已注册的解析器。
  static List<BillParser> get all => List<BillParser>.unmodifiable(_parsers);

  /// 按来源取解析器。
  static BillParser? forSource(BillSource source) {
    for (final parser in _parsers) {
      if (parser.source == source) {
        return parser;
      }
    }
    return null;
  }

  /// 已实现导入的来源列表。
  static List<BillSource> get supportedSources =>
      _parsers.map((parser) => parser.source).toList(growable: false);
}
