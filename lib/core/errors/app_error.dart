/// 应用内异常体系。
///
/// 区分「可预期的业务失败」与「真正的 bug」：
/// - 可预期失败（单行解析错误、表头缺失、编码异常）→ 用这里的异常，UI 要给出可读原因
/// - 真正的 bug → 让它们自然抛出，不要用这里包一层
///
/// 参见 docs/IMPORT_FORMATS.md §5.4。
library;

/// 应用异常基类。
class AppException implements Exception {
  const AppException(this.message, {this.detail});

  /// 面向用户的可读原因。
  final String message;

  /// 可选的补充细节（例如具体是哪个字段、哪一行）。
  final String? detail;

  @override
  String toString() => detail == null ? message : '$message（$detail）';
}

/// 账单解析过程中的可预期失败。
///
/// 注意：单行解析失败**不应该**抛出这个异常来中断整个导入，
/// 而应被收集进 `ParseError` 列表。这个异常用于「整份文件无法处理」的情况。
class ParseException extends AppException {
  const ParseException(super.message, {super.detail});
}

/// 找不到可识别的表头行。
class HeaderNotFoundException extends ParseException {
  const HeaderNotFoundException()
      : super(
          '无法识别账单表头',
          detail: '未找到同时包含「交易时间」与「金额」列的行',
        );
}

/// 无法自动识别账单来源。
///
/// UI 捕获后应展示「无法自动识别，请选择账单来源」并提供微信 / 支付宝选项。
class SourceNotDeterminedException extends ParseException {
  const SourceNotDeterminedException()
      : super(
          '无法自动识别账单来源',
          detail: '表头特征与文件名都未命中已知来源，请手动选择',
        );
}

/// 编码解码失败。
class DecodeException extends AppException {
  const DecodeException(super.message, {super.detail});
}

/// 文件格式不支持（如旧版 .xls）。
class UnsupportedFormatException extends AppException {
  const UnsupportedFormatException(super.message, {super.detail});
}

/// 数据库层异常。
class DatabaseException extends AppException {
  const DatabaseException(super.message, {super.detail});
}
