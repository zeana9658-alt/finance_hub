import 'package:intl/intl.dart';

/// 账单时间解析。
///
/// 账单里的时间一律视为**用户本地时间**（账单本身就是按本地时间导出的），
/// 因此这里返回的 [DateTime] 是本地时间。
///
/// **解析失败返回 `null`** —— 调用方必须记为错误行，
/// **绝对不要用 `DateTime.now()` 兜底**（那会把坏数据伪装成今天的交易）。
///
/// 支持格式（见 docs/IMPORT_FORMATS.md §5.3）：
/// ```text
/// 2026-10-05 08:30:00
/// 2026-10-05 08:30
/// 2026/10/05 08:30:00
/// 2026/10/5 8:30
/// 2026年10月05日 08:30:00
/// 2026-10-05
/// 2026/10/05
/// 20261005083000
/// ```
DateTime? tryParseBillDateTime(String raw) {
  var s = raw
      .replaceAll('\uFEFF', '')
      .replaceAll('\u3000', ' ')
      .replaceAll('/', '-')
      .replaceAll('年', '-')
      .replaceAll('月', '-')
      .replaceAll('日', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  if (s.isEmpty) {
    return null;
  }

  // 紧凑格式 20261005083000 / 20261005
  if (RegExp(r'^\d{8}$').hasMatch(s)) {
    return _fromParts(
      int.parse(s.substring(0, 4)),
      int.parse(s.substring(4, 6)),
      int.parse(s.substring(6, 8)),
    );
  }
  if (RegExp(r'^\d{14}$').hasMatch(s)) {
    return _fromParts(
      int.parse(s.substring(0, 4)),
      int.parse(s.substring(4, 6)),
      int.parse(s.substring(6, 8)),
      int.parse(s.substring(8, 10)),
      int.parse(s.substring(10, 12)),
      int.parse(s.substring(12, 14)),
    );
  }

  // 先试 Dart 原生解析（对 ISO 风格最快）
  final direct = DateTime.tryParse(s);
  if (direct != null) {
    return direct;
  }

  for (final pattern in _patterns) {
    try {
      return DateFormat(pattern).parseLoose(s);
    } on FormatException {
      continue;
    }
  }
  return null;
}

const List<String> _patterns = <String>[
  'yyyy-MM-dd HH:mm:ss',
  'yyyy-MM-dd HH:mm',
  'yyyy-M-d HH:mm:ss',
  'yyyy-M-d HH:mm',
  'yyyy-M-d',
  'yyyy-MM-dd',
];

DateTime? _fromParts(
  int year,
  int month,
  int day, [
  int hour = 0,
  int minute = 0,
  int second = 0,
]) {
  if (month < 1 || month > 12 || day < 1 || day > 31) {
    return null;
  }
  return DateTime(year, month, day, hour, minute, second);
}
