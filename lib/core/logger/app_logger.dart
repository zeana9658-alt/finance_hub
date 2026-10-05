import 'dart:developer' as developer;

/// 统一日志出口。
///
/// 隐私约束（见 docs/PRIVACY.md §5）：
/// - **禁止**打印完整账单原文、商户名、订单号、银行卡号
/// - release 模式下只输出 WARN 及以上
/// - 所有消息在输出前经过 [_sanitize] 脱敏
///
/// 使用 [AppLogger] 而非 `print`，`avoid_print` lint 会拦截 `print`。
enum LogLevel { debug, info, warn, error }

class AppLogger {
  AppLogger._();

  /// 低于此级别的日志不输出。release 构建下应设为 [LogLevel.warn]。
  static LogLevel minLevel = LogLevel.debug;

  static void debug(String message) => _log(LogLevel.debug, message);

  static void info(String message) => _log(LogLevel.info, message);

  static void warn(String message) => _log(LogLevel.warn, message);

  static void error(String message, [Object? error, StackTrace? stackTrace]) =>
      _log(LogLevel.error, message, error: error, stackTrace: stackTrace);

  /// 疑似卡号 / 身份证 / 长数字串，输出前脱敏。
  static final RegExp _longDigits = RegExp(r'\d{11,}');

  static void _log(
    LogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (level.index < minLevel.index) {
      return;
    }
    developer.log(
      _sanitize(message),
      name: 'FinanceHub',
      level: _numericLevel(level),
      error: error == null ? null : _sanitize(error.toString()),
      stackTrace: stackTrace,
    );
  }

  static int _numericLevel(LogLevel level) => switch (level) {
        LogLevel.debug => 500,
        LogLevel.info => 800,
        LogLevel.warn => 900,
        LogLevel.error => 1000,
      };

  /// 把长数字串替换为掩码，只保留后 4 位。
  static String _sanitize(String message) {
    return message.replaceAllMapped(_longDigits, (match) {
      final digits = match.group(0)!;
      return '****${digits.substring(digits.length - 4)}';
    });
  }
}
