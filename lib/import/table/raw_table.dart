import 'dart:math' as math;

/// 统一二维表模型。
///
/// CSV / XLSX / 粘贴文本三种输入形态都先被读成 [RawTable]，
/// 之后的表头定位、列映射、解析全部只认这个模型 ——
/// 这样新增一种输入格式时，下游一行代码都不用改。
///
/// 参考 `lemon970/jizhang-app` 的 `decode → parse-*` 分层，
/// 在表格与解析之间插入这一层。
class RawTable {
  const RawTable(this.rows, {this.origin = ''});

  /// 行优先的单元格矩阵。每个单元格已 trim。
  final List<List<String>> rows;

  /// 来源描述（文件名或 `粘贴文本`），用于来源识别与错误提示。
  final String origin;

  bool get isEmpty => rows.isEmpty;

  int get rowCount => rows.length;

  int get columnCount =>
      rows.isEmpty ? 0 : rows.map((row) => row.length).reduce(math.max);

  /// 取第 [index] 行，越界返回空列表（不抛异常，便于容错解析）。
  List<String> rowAt(int index) {
    if (index < 0 || index >= rows.length) {
      return const <String>[];
    }
    return rows[index];
  }

  /// 前 [count] 行拼成一段文本，用于来源识别。
  String headText({int count = 8}) => rows
      .take(count)
      .map((row) => row.join(' '))
      .join(' ');

  static const RawTable empty = RawTable(<List<String>>[]);

  @override
  String toString() => 'RawTable(${rows.length} 行 × $columnCount 列, origin=$origin)';
}
