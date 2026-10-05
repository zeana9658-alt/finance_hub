/// 文本归一化工具。
///
/// 这些函数直接参与**去重指纹**的计算（见 docs/DATABASE.md §3.5），
/// 改动它们会导致历史数据的 `unique_key` 失效，务必谨慎。
library;

final RegExp _whitespaceRun = RegExp(r'\s+');

/// 把连续空白（含全角空格、Tab、换行）折叠为单个半角空格，并去掉首尾空白。
///
/// 商户名与描述在指纹中参与哈希，必须先把「视觉上相同但字节不同」的情况归一。
String collapseWhitespace(String input) =>
    input.replaceAll('\u3000', ' ').replaceAll(_whitespaceRun, ' ').trim();

/// 归一化商户名用于指纹计算。
///
/// - 折叠空白
/// - **不转小写**：商户名的大小写有语义（`Lawson` vs `lawson` 是同一家，
///   但 `ABC` 与 `abc` 也可能是不同商户），保守起见保留原样。
/// - 去掉常见的前后缀噪音（如「-」连接的分店后缀不做处理，避免误合并）
String normalizeMerchantForFingerprint(String input) => collapseWhitespace(input);

/// 归一化描述用于指纹计算。
String normalizeDescriptionForFingerprint(String input) =>
    collapseWhitespace(input);

/// 归一化支付方式用于指纹计算。
String normalizePaymentMethodForFingerprint(String input) =>
    collapseWhitespace(input);

/// 归一化交易单号。
///
/// 平台导出的单号有时带首尾空格、Tab，或全角字符。
String normalizeExternalId(String input) {
  var s = collapseWhitespace(input);
  // 全角数字 / 字母 → 半角
  s = s.replaceAllMapped(RegExp('[\uFF10-\uFF19]'), (m) {
    final code = m.group(0)!.codeUnitAt(0);
    return String.fromCharCode(code - 0xFF10 + 0x30);
  });
  s = s.replaceAllMapped(RegExp('[\uFF21-\uFF3A\uFF41-\uFF5A]'), (m) {
    final code = m.group(0)!.codeUnitAt(0);
    return code >= 0xFF41
        ? String.fromCharCode(code - 0xFF41 + 0x61)
        : String.fromCharCode(code - 0xFF21 + 0x41);
  });
  // 单号统一大写，避免大小写差异导致同号不同键
  return s.toUpperCase();
}

/// 归一化商户名，作为 `merchant_rules.merchant_key`。
///
/// 与指纹用的归一化不同：这里**要转小写并去掉符号**，
/// 因为商户记忆是「模糊匹配」，希望 `Lawson 罗森` 与 `Lawson罗森` 命中同一条记忆。
String merchantKeyOf(String merchant) {
  final collapsed = collapseWhitespace(merchant).toLowerCase();
  return collapsed.replaceAll(RegExp(r'[\s\-_·・.,，。()（）\[\]【】]'), '');
}
