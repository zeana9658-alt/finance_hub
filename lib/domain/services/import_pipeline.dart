import 'package:finance_hub/core/errors/app_error.dart';
import 'package:finance_hub/core/utils/hash_utils.dart';
import 'package:finance_hub/domain/entities/normalized_transaction.dart';
import 'package:finance_hub/domain/enums/bill_source.dart';
import 'package:finance_hub/domain/services/categorization_engine.dart';
import 'package:finance_hub/domain/services/duplicate_detector.dart';
import 'package:finance_hub/import/decode/text_decoder.dart';
import 'package:finance_hub/import/detect/source_detector.dart';
import 'package:finance_hub/import/models/import_candidate.dart';
import 'package:finance_hub/import/models/import_preview.dart';
import 'package:finance_hub/import/parsers/parser_registry.dart';
import 'package:finance_hub/import/table/csv_reader.dart';
import 'package:finance_hub/import/table/raw_table.dart';
import 'package:finance_hub/import/table/text_table_reader.dart';
import 'package:finance_hub/import/table/xlsx_reader.dart';
import 'package:path/path.dart' as p;

/// 导入流水线 —— 把「一份账单输入」变成「一个可确认的导入预览」。
///
/// 严格按 docs/ARCHITECTURE.md §3.1 的 11 步执行，**全程不写数据库**：
///
/// ```
/// 解码 → 读表 → 定位表头 → 识别来源 → 解析 → 判重 → 分类 → 构建预览
/// ```
///
/// 这是一个**纯函数式服务**（除了读入的字节），因此可以在测试里
/// 用 fixtures 直接跑，不需要数据库、不需要 Flutter。
class ImportPipeline {
  const ImportPipeline({
    this.duplicateDetector = const DuplicateDetector(),
    this.categorizationEngine = const CategorizationEngine(),
  });

  final DuplicateDetector duplicateDetector;
  final CategorizationEngine categorizationEngine;

  /// 从文件字节构建预览（自动按扩展名选择读取器）。
  ImportPreview previewFile({
    required String path,
    required List<int> bytes,
    BillSource? forcedSource,
    Set<String> existingUniqueKeys = const <String>{},
    List<TransactionProbe> existingProbes = const <TransactionProbe>[],
    Map<int, String> categoryNames = const <int, String>{},
  }) {
    final lower = path.toLowerCase();

    if (lower.endsWith('.xls')) {
      throw const UnsupportedFormatException(
        '旧版 .xls 暂未支持',
        detail: '请在微信/支付宝导出时选择 CSV 或 XLSX 格式',
      );
    }

    final RawTable table;
    String? encodingNote;
    if (lower.endsWith('.xlsx')) {
      table = XlsxReader.read(bytes, origin: path);
    } else {
      final decoded = TextDecoder.decode(bytes);
      encodingNote = decoded.encoding;
      table = CsvReader.read(decoded.text, origin: path);
    }

    final preview = buildPreview(
      table: table,
      label: _fileName(path),
      filePath: path,
      fileHash: sha1HexOfBytes(bytes),
      forcedSource: forcedSource,
      existingUniqueKeys: existingUniqueKeys,
      existingProbes: existingProbes,
      categoryNames: categoryNames,
    );
    return encodingNote == null ? preview : preview;
  }

  /// 从粘贴的表格文本构建预览。
  ImportPreview previewText(
    String text, {
    BillSource? forcedSource,
    Set<String> existingUniqueKeys = const <String>{},
    List<TransactionProbe> existingProbes = const <TransactionProbe>[],
    Map<int, String> categoryNames = const <int, String>{},
  }) {
    final table = TextTableReader.read(text);
    return buildPreview(
      table: table,
      label: '粘贴文本',
      forcedSource: forcedSource,
      existingUniqueKeys: existingUniqueKeys,
      existingProbes: existingProbes,
      categoryNames: categoryNames,
    );
  }

  /// 核心：从统一表格模型构建预览。
  ///
  /// 抛 [SourceNotDeterminedException] 表示无法自动识别来源，
  /// 调用方应让用户手动选择后再用 [forcedSource] 重试。
  ImportPreview buildPreview({
    required RawTable table,
    required String label,
    BillSource? forcedSource,
    String? filePath,
    String? fileHash,
    Set<String> existingUniqueKeys = const <String>{},
    List<TransactionProbe> existingProbes = const <TransactionProbe>[],
    Map<int, String> categoryNames = const <int, String>{},
  }) {
    final detection = SourceDetector.detect(table);
    final source = forcedSource ?? detection.source;
    if (source == null) {
      throw const SourceNotDeterminedException();
    }

    final parser = ParserRegistry.forSource(source);
    if (parser == null) {
      throw UnsupportedFormatException('暂不支持解析「${source.label}」账单');
    }

    final result = parser.parse(table);

    // 判重（强重复 + 疑似跨平台）
    final scan = duplicateDetector.scan(
      result.transactions,
      existingUniqueKeys: existingUniqueKeys,
      existingProbes: existingProbes,
    );

    final drafts = <_CandidateDraft>[];

    // 成功行 → 候选
    for (var i = 0; i < result.parsed.length; i++) {
      final item = result.parsed[i];
      final verdict = scan.verdicts[i];

      // 分类（三级优先级）
      final assignment = categorizationEngine.categorize(item.transaction);
      final transaction = item.transaction.copyWith(
        categoryId: assignment.categoryId,
        subcategoryId: assignment.subcategoryId,
        categorySource: assignment.source,
      );

      final status = verdict.isDuplicate
          ? CandidateStatus.duplicate
          : CandidateStatus.valid;

      drafts.add(
        _CandidateDraft(
          rowNumber: item.rowNumber,
          status: status,
          transaction: transaction,
          rawSummary: item.rawSummary,
          isSuspectedCrossPlatform: verdict.isSuspectedCrossPlatform,
          categoryLabel: _labelOf(transaction.categoryId,
              transaction.subcategoryId, categoryNames),
          // 重复项默认不勾选；其余按交易状态/类型决定
          isSelected:
              status == CandidateStatus.valid && transaction.defaultSelectedInImport,
        ),
      );
    }

    // 错误行 → 候选
    for (final error in result.errors) {
      drafts.add(
        _CandidateDraft(
          rowNumber: error.rowNumber,
          status: CandidateStatus.error,
          transaction: null,
          rawSummary: error.rawSummary,
          errorReason: error.reason,
          isSelected: false,
        ),
      );
    }

    // 按原始行号排序，让用户核对时行号连续
    drafts.sort((a, b) => a.rowNumber.compareTo(b.rowNumber));

    final candidates = <ImportCandidate>[];
    for (var i = 0; i < drafts.length; i++) {
      candidates.add(drafts[i].toCandidate(i));
    }

    return ImportPreview(
      label: label,
      source: source,
      detectionBasis: forcedSource == null
          ? detection.basis
          : DetectionBasis.manual,
      createdAt: DateTime.now(),
      candidates: candidates,
      totalDataRows: result.totalDataRows,
      headerRowNumber: result.headerRowNumber,
      filePath: filePath,
      fileHash: fileHash,
    );
  }

  String _labelOf(
    int? categoryId,
    int? subcategoryId,
    Map<int, String> names,
  ) {
    final top = categoryId == null ? null : names[categoryId];
    if (top == null || top.isEmpty) {
      return '';
    }
    final sub = subcategoryId == null ? null : names[subcategoryId];
    if (sub == null || sub.isEmpty) {
      return top;
    }
    return '$top / $sub';
  }

  String _fileName(String path) {
    final name = p.basename(path);
    return name.isEmpty ? path : name;
  }
}

/// 构建候选过程中的中间结构。
class _CandidateDraft {
  _CandidateDraft({
    required this.rowNumber,
    required this.status,
    required this.transaction,
    required this.rawSummary,
    this.errorReason = '',
    this.isSuspectedCrossPlatform = false,
    this.categoryLabel = '',
    this.isSelected = false,
  });

  final int rowNumber;
  final CandidateStatus status;
  final NormalizedTransaction? transaction;
  final String rawSummary;
  final String errorReason;
  final bool isSuspectedCrossPlatform;
  final String categoryLabel;
  final bool isSelected;

  ImportCandidate toCandidate(int index) => ImportCandidate(
        index: index,
        status: status,
        transaction: transaction,
        rowNumber: rowNumber,
        rawSummary: rawSummary,
        errorReason: errorReason,
        isSuspectedCrossPlatform: isSuspectedCrossPlatform,
        categoryLabel: categoryLabel,
        isSelected: isSelected,
      );
}
