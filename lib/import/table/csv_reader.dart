import 'package:csv/csv.dart';
import 'package:finance_hub/import/table/raw_table.dart';

/// CSV 读取器。
///
/// **关键**：使用符合 RFC 4180 的解析器，而不是 `line.split(',')`。
/// 账单的商品名里出现英文逗号（如 `示例超市, 生鲜`）时，朴素切分会让
/// 整行列位错乱，金额被读成别的字段。
///
/// 参考项目 `changdaye/bill-aggregator` 用的是 `line.split(',')`，这是它的
/// 主要缺陷之一（见 docs/GITHUB_RESEARCH.md §3.4）。
class CsvReader {
  CsvReader._();

  /// 把 CSV 文本解析为 [RawTable]。
  static RawTable read(String text, {String origin = ''}) {
    final cleaned = text
        .replaceFirst('\uFEFF', '')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');

    if (cleaned.trim().isEmpty) {
      return RawTable(const <List<String>>[], origin: origin);
    }

    final converter = Csv(
      fieldDelimiter: ',',
      autoDetect: false,
      dynamicTyping: false,
      skipEmptyLines: true,
    );

    final List<List<dynamic>> decoded;
    try {
      decoded = converter.decode(cleaned);
    } on Exception {
      // 解析器抛异常时退化为逐行按逗号切分，保证不整体失败。
      return _fallbackSplit(cleaned, origin);
    }

    final rows = decoded
        .map(
          (row) => row
              .map((cell) => cell == null ? '' : cell.toString().trim())
              .toList(),
        )
        .toList();

    return RawTable(rows, origin: origin);
  }

  /// 兜底：解析器彻底失败时按逗号切分（会有列位风险，但优于整份失败）。
  static RawTable _fallbackSplit(String text, String origin) {
    final rows = text
        .split('\n')
        .map((line) => line.split(',').map((cell) => cell.trim()).toList())
        .toList();
    return RawTable(rows, origin: origin);
  }
}
