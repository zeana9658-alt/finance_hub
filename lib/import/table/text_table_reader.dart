import 'package:csv/csv.dart';
import 'package:finance_hub/import/table/raw_table.dart';

/// 粘贴表格文本读取器。
///
/// 用户从账单页面复制出来的内容通常是 Tab 分隔（也可能是逗号分隔）。
/// 自动判别：
/// - 若文本含 Tab 且不含逗号 → 按 Tab 切分
/// - 否则 → 交给 CSV 解析器
///
/// 对应 brief 第 5 条「复制表格文本」的输入形态。
class TextTableReader {
  TextTableReader._();

  static RawTable read(String text, {String origin = '粘贴文本'}) {
    final cleaned = text
        .replaceFirst('\uFEFF', '')
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');

    if (cleaned.trim().isEmpty) {
      return RawTable(const <List<String>>[], origin: origin);
    }

    final useTab = cleaned.contains('\t') && !cleaned.contains(',');

    if (useTab) {
      final rows = cleaned
          .split('\n')
          .map((line) => line.split('\t').map((cell) => cell.trim()).toList())
          .toList();
      return RawTable(rows, origin: origin);
    }

    final converter = Csv(
      fieldDelimiter: ',',
      autoDetect: false,
      dynamicTyping: false,
      skipEmptyLines: true,
    );
    final decoded = converter.decode(cleaned);
    final rows = decoded
        .map(
          (List<dynamic> row) => row
              .map((dynamic cell) => cell == null ? '' : cell.toString().trim())
              .toList(),
        )
        .toList();
    return RawTable(rows, origin: origin);
  }
}
