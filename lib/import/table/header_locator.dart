import 'package:finance_hub/import/models/raw_bill_row.dart';
import 'package:finance_hub/import/table/header_normalizer.dart';
import 'package:finance_hub/import/table/raw_table.dart';

/// 列别名表 —— 定义「哪些列名算同一列」。
///
/// 一套别名吃下微信与支付宝的**所有导出版本**（见 docs/IMPORT_FORMATS.md §3.1 / §4.2）。
/// 新增来源时只需在这里补别名，不必改解析逻辑。
class ColumnAliases {
  ColumnAliases._();

  /// 交易时间。顺序即优先级：`交易时间` > `交易创建时间` > `付款时间`。
  static const List<String> time = <String>[
    '交易时间',
    '交易创建时间',
    '付款时间',
    '创建时间',
    '交易日期',
    '时间',
    '日期',
  ];

  /// 金额。
  static const List<String> amount = <String>[
    '金额',
    '交易金额',
    '发生额',
    '金额元',
  ];

  /// 平台原始类型文本（微信「商户消费」等）。
  static const List<String> typeRaw = <String>[
    '交易类型',
    '类型',
    '业务类型',
  ];

  /// 平台原始分类（支付宝新版「交易分类」）。
  static const List<String> category = <String>[
    '交易分类',
    '分类',
    '类别',
  ];

  static const List<String> merchant = <String>[
    '交易对方',
    '对方账号',
    '对方',
    '商户',
    '商家',
    '收付款方',
  ];

  static const List<String> description = <String>[
    '商品说明',
    '商品名称',
    '商品',
    '交易说明',
    '摘要',
  ];

  static const List<String> direction = <String>[
    '收支',
    '收支类型',
    '收支方向',
    '资金方向',
  ];

  static const List<String> paymentMethod = <String>[
    '支付方式',
    '收付款方式',
    '付款方式',
    '交易来源地',
    '资金来源',
  ];

  static const List<String> status = <String>[
    '当前状态',
    '交易状态',
    '状态',
    '资金状态',
  ];

  static const List<String> externalId = <String>[
    '交易单号',
    '交易订单号',
    '交易号',
    '订单号',
    '商户单号',
    '商家订单号',
    '流水号',
  ];

  static const List<String> note = <String>[
    '备注',
    '附言',
  ];
}

/// 已定位的表头：记录表头行号 + 各语义列的下标。
///
/// 未找到的列为 `-1`，取值时返回空字符串，不会抛异常。
class LocatedHeader {
  const LocatedHeader({
    required this.rowIndex,
    required this.rawHeaders,
    required this.normalizedHeaders,
    required this.timeIndex,
    required this.amountIndex,
    this.typeIndex = -1,
    this.categoryIndex = -1,
    this.merchantIndex = -1,
    this.descriptionIndex = -1,
    this.directionIndex = -1,
    this.paymentMethodIndex = -1,
    this.statusIndex = -1,
    this.externalIdIndex = -1,
    this.noteIndex = -1,
  });

  /// 表头在 [RawTable.rows] 中的下标（0-based）。
  final int rowIndex;

  final List<String> rawHeaders;
  final List<String> normalizedHeaders;

  final int timeIndex;
  final int amountIndex;
  final int typeIndex;
  final int categoryIndex;
  final int merchantIndex;
  final int descriptionIndex;
  final int directionIndex;
  final int paymentMethodIndex;
  final int statusIndex;
  final int externalIdIndex;
  final int noteIndex;

  /// 表头在原始文件中的行号（1-based），用于错误提示。
  int get rowNumber => rowIndex + 1;

  /// 数据区起始下标。
  int get dataStartIndex => rowIndex + 1;

  /// 从一行单元格中抽出语义字段。
  RawBillRow extract(List<String> cells, int rowNumber) => RawBillRow(
        rowNumber: rowNumber,
        rawCells: cells,
        timeText: cellAt(cells, timeIndex),
        typeText: cellAt(cells, typeIndex),
        categoryText: cellAt(cells, categoryIndex),
        merchantText: cellAt(cells, merchantIndex),
        descriptionText: cellAt(cells, descriptionIndex),
        directionText: cellAt(cells, directionIndex),
        amountText: cellAt(cells, amountIndex),
        paymentMethodText: cellAt(cells, paymentMethodIndex),
        statusText: cellAt(cells, statusIndex),
        externalIdText: cellAt(cells, externalIdIndex),
        noteText: cellAt(cells, noteIndex),
      );

  /// 安全取值：越界返回空字符串。
  static String cellAt(List<String> cells, int index) {
    if (index < 0 || index >= cells.length) {
      return '';
    }
    return cells[index].trim();
  }

  @override
  String toString() =>
      'LocatedHeader(第 $rowNumber 行, 时间=$timeIndex, 金额=$amountIndex)';
}

/// 表头定位器。
///
/// 微信/支付宝账单的前几行是说明文字，真实表头不在第 1 行。
/// 本定位器扫描前 [maxScanRows] 行，找出**同时含时间列与金额列**的那一行。
///
/// 关键决策：**不硬编码行号**。参考项目 `changdaye/bill-aggregator` 写死
/// `lines[4]`，一旦平台调整说明文字行数就崩；本项目改为扫描。
class HeaderLocator {
  HeaderLocator._();

  /// 最多扫描的行数。防止畸形文件里无限扫描（借鉴
  /// `zalexrose/FamilyFinanceManager` 的 `range(min(20, len(df)))`）。
  static const int maxScanRows = 30;

  /// 定位表头。返回 `null` 表示未找到。
  static LocatedHeader? locate(RawTable table) {
    final limit =
        table.rowCount < maxScanRows ? table.rowCount : maxScanRows;

    for (var i = 0; i < limit; i++) {
      final normalized = HeaderNormalizer.normalizeRow(table.rowAt(i));
      final timeIndex = findColumn(normalized, ColumnAliases.time);
      final amountIndex = findColumn(normalized, ColumnAliases.amount);
      if (timeIndex >= 0 && amountIndex >= 0) {
        return LocatedHeader(
          rowIndex: i,
          rawHeaders: table.rowAt(i),
          normalizedHeaders: normalized,
          timeIndex: timeIndex,
          amountIndex: amountIndex,
          typeIndex: findColumn(normalized, ColumnAliases.typeRaw),
          categoryIndex: findColumn(normalized, ColumnAliases.category),
          merchantIndex: findColumn(normalized, ColumnAliases.merchant),
          descriptionIndex: findColumn(normalized, ColumnAliases.description),
          directionIndex: findColumn(normalized, ColumnAliases.direction),
          paymentMethodIndex:
              findColumn(normalized, ColumnAliases.paymentMethod),
          statusIndex: findColumn(normalized, ColumnAliases.status),
          externalIdIndex: findColumn(normalized, ColumnAliases.externalId),
          noteIndex: findColumn(normalized, ColumnAliases.note),
        );
      }
    }
    return null;
  }

  /// 在归一化表头中查找列下标。
  ///
  /// 两轮匹配：先精确相等，再包含。两轮都按别名顺序遍历，
  /// 因此别名列表的顺序就是优先级。
  static int findColumn(List<String> normalizedHeaders, List<String> aliases) {
    for (final alias in aliases) {
      for (var i = 0; i < normalizedHeaders.length; i++) {
        if (normalizedHeaders[i] == alias) {
          return i;
        }
      }
    }
    for (final alias in aliases) {
      for (var i = 0; i < normalizedHeaders.length; i++) {
        if (normalizedHeaders[i].contains(alias)) {
          return i;
        }
      }
    }
    return -1;
  }
}
