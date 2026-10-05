import 'package:excel/excel.dart';
import 'package:finance_hub/import/table/raw_table.dart';

/// XLSX 读取器。
///
/// 使用纯 Dart 的 `excel` 包，Android 与 Windows 行为一致。
///
/// 注意：**不支持旧版 `.xls`**（二进制 OLE 格式）。检测到 `.xls` 时由上层
/// 抛出 `UnsupportedFormatException` 并给出明确提示，而不是崩溃或静默失败。
class XlsxReader {
  XlsxReader._();

  /// 读取字节内容，取第一个工作表。
  ///
  /// [origin] 仅用于调试与来源识别。
  static RawTable read(List<int> bytes, {String origin = ''}) {
    final Excel workbook;
    try {
      workbook = Excel.decodeBytes(bytes);
    } on Exception catch (error) {
      throw FormatException('XLSX 文件无法解码：$error');
    }

    final rows = <List<String>>[];
    for (final tableName in workbook.tables.keys) {
      final sheet = workbook.tables[tableName];
      if (sheet == null) {
        continue;
      }
      for (final row in sheet.rows) {
        rows.add(
          row
              .map((cell) => cell?.value?.toString().trim() ?? '')
              .toList(growable: false),
        );
      }
      // 只读第一个工作表 —— 微信/支付宝账单只有一个 sheet。
      break;
    }

    return RawTable(rows, origin: origin);
  }
}
