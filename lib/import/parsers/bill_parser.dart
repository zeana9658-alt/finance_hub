import 'dart:convert';

import 'package:finance_hub/core/errors/app_error.dart';
import 'package:finance_hub/core/money/money.dart';
import 'package:finance_hub/core/utils/date_parser.dart';
import 'package:finance_hub/domain/entities/normalized_transaction.dart';
import 'package:finance_hub/domain/enums/bill_source.dart';
import 'package:finance_hub/domain/enums/category_source.dart';
import 'package:finance_hub/domain/enums/transaction_status.dart';
import 'package:finance_hub/domain/enums/transaction_type.dart';
import 'package:finance_hub/domain/services/transaction_fingerprint.dart';
import 'package:finance_hub/import/models/parse_error.dart';
import 'package:finance_hub/import/models/parse_result.dart';
import 'package:finance_hub/import/models/raw_bill_row.dart';
import 'package:finance_hub/import/table/header_locator.dart';
import 'package:finance_hub/import/table/raw_table.dart';

/// 账单解析器抽象基类。
///
/// 借鉴 `zalexrose/FamilyFinanceManager` 的 `BaseAdapter`，但有两处关键改进：
/// 1. 返回 [ParseResult]（含错误行）而不是只返回成功列表 —— 错误必须可见
/// 2. 把「表格读取 + 表头定位 + 列映射」抽到上游，子类只关心「值 → 交易」
///
/// 新增来源（京东/银行卡/信用卡）只需继承本类并实现
/// [source]、[excludeTypeKeywords]、[normalizeRow]。
abstract class BillParser {
  /// 本解析器对应的来源。
  BillSource get source;

  /// 资金搬运类「交易类型」关键词。
  ///
  /// 命中后该行标记为 [TransactionType.transfer]（默认不勾选导入），
  /// 而不是直接丢弃 —— 用户可能仍想追踪资金流向。
  ///
  /// 来源：`zalexrose/FamilyFinanceManager` 的 `exclude_types`，
  /// 并升级为「标记而非丢弃」。
  List<String> get excludeTypeKeywords => const <String>[];

  /// 「交易类型」中出现即判定为退款的关键词。
  List<String> get refundTypeKeywords => const <String>['退款'];

  /// 解析整张表。
  ///
  /// 表头无法识别时抛 [HeaderNotFoundException]；
  /// 单行解析失败不中断，收集进 [ParseResult.errors]。
  ParseResult parse(RawTable table) {
    final header = HeaderLocator.locate(table);
    if (header == null) {
      throw const HeaderNotFoundException();
    }

    final parsed = <ParsedTransaction>[];
    final errors = <ParseError>[];
    var dataRows = 0;

    for (var i = header.dataStartIndex; i < table.rowCount; i++) {
      final cells = table.rowAt(i);
      final rowNumber = i + 1;
      final row = header.extract(cells, rowNumber);

      if (row.isBlank || row.isSeparator) {
        continue;
      }
      dataRows++;

      try {
        final transaction = normalizeRow(row);
        if (transaction != null) {
          parsed.add(
            ParsedTransaction(
              rowNumber: rowNumber,
              transaction: transaction,
              rawSummary: row.rawSummary,
            ),
          );
        }
      } on ParseException catch (error) {
        errors.add(
          ParseError(
            rowNumber: rowNumber,
            rawSummary: row.rawSummary,
            reason: error.toString(),
            rawJson: _rawJson(row),
          ),
        );
      } on Exception catch (error) {
        errors.add(
          ParseError(
            rowNumber: rowNumber,
            rawSummary: row.rawSummary,
            reason: '未预期的解析失败：$error',
            rawJson: _rawJson(row),
          ),
        );
      }
    }

    return ParseResult(
      parsed: parsed,
      errors: errors,
      totalDataRows: dataRows,
      headerRowNumber: header.rowNumber,
    );
  }

  /// 把一行语义字段转成统一交易实体。
  ///
  /// 返回 `null` 表示「该行应被跳过且不算错误」（目前各实现都不返回 null，
  /// 保留这个约定以便将来处理特殊行）。
  /// 抛 [ParseException] 表示「该行是坏数据」，会被记入错误列表。
  NormalizedTransaction? normalizeRow(RawBillRow row);

  // ───────────────────────── 供子类使用的工具 ─────────────────────────

  /// 解析金额，失败抛 [ParseException]。
  ///
  /// 返回**绝对值**（单位：分）。方向由 [TransactionType] 表达。
  int requireAmountCents(String raw) {
    final cents = parseMoneyToCents(raw);
    if (cents == null) {
      throw ParseException('金额字段无法解析', detail: _short(raw));
    }
    return cents.abs();
  }

  /// 解析时间，失败抛 [ParseException]。
  DateTime requireDateTime(String raw) {
    final parsed = tryParseBillDateTime(raw);
    if (parsed == null) {
      throw ParseException('时间字段无法识别', detail: _short(raw));
    }
    return parsed;
  }

  /// 归一化普通字段：微信/支付宝用 `/`、`-`、`—` 表示「无内容」。
  ///
  /// 商户名、商品名、备注都要过这一层，否则会得到 `merchant = '/'` 这种脏数据。
  String cleanField(String raw) {
    final s = raw.trim();
    if (s.isEmpty || s == '/' || s == '-' || s == '—' || s == '\\') {
      return '';
    }
    return s;
  }

  /// 归一化备注（语义同 [cleanField]，保留别名以便阅读）。
  String cleanNote(String raw) => cleanField(raw);

  /// 判断「交易类型」是否属于资金搬运。
  bool isTransferType(String typeText) {
    if (typeText.isEmpty) {
      return false;
    }
    for (final keyword in excludeTypeKeywords) {
      if (typeText.contains(keyword)) {
        return true;
      }
    }
    return false;
  }

  /// 判断「交易类型」是否属于退款。
  bool isRefundType(String typeText) {
    for (final keyword in refundTypeKeywords) {
      if (typeText.contains(keyword)) {
        return true;
      }
    }
    return false;
  }

  /// 组装最终实体 —— 统一处理指纹、时间戳、默认分类来源。
  NormalizedTransaction buildTransaction({
    required BillSource source,
    String? sourceTransactionId,
    required DateTime transactionTime,
    required String transactionTimeRaw,
    required TransactionType transactionType,
    required String transactionTypeRaw,
    String platformCategory = '',
    required int amountCents,
    required String merchant,
    required String description,
    required String paymentMethod,
    required TransactionStatus status,
    String note = '',
    RawBillRow? row,
    DateTime? now,
  }) {
    final timestamp = now ?? DateTime.now();
    final externalId = sourceTransactionId?.trim() ?? '';
    final uniqueKey = TransactionFingerprint.compute(
      source: source,
      externalId: externalId.isEmpty ? null : externalId,
      transactionTime: transactionTime,
      amountCents: amountCents,
      merchant: merchant,
      description: description,
      paymentMethod: paymentMethod,
    );

    return NormalizedTransaction(
      source: source,
      sourceTransactionId: externalId.isEmpty ? null : externalId,
      uniqueKey: uniqueKey,
      transactionTime: transactionTime,
      transactionTimeRaw: transactionTimeRaw,
      transactionType: transactionType,
      transactionTypeRaw: transactionTypeRaw,
      platformCategory: platformCategory,
      amountCents: amountCents,
      merchant: merchant,
      description: description,
      categorySource: CategorySource.fallback,
      paymentMethod: paymentMethod,
      status: status,
      note: note,
      rawData: row == null ? null : _rawJson(row),
      createdAt: timestamp,
      updatedAt: timestamp,
    );
  }

  String _rawJson(RawBillRow row) =>
      jsonEncode(<String, Object?>{
        'row': row.rowNumber,
        'cells': row.rawCells,
      });

  String _short(String value) {
    final s = value.trim();
    if (s.length <= 40) {
      return '「$s」';
    }
    return '「${s.substring(0, 40)}…」';
  }
}
