/// 表头归一化。
///
/// 让不同导出格式、不同括号写法的列名归一到同一个键，例如：
///
/// ```text
/// '金额(元)'   -> '金额'
/// '金额（元）' -> '金额'
/// '金额 (元)'  -> '金额'
/// '金额'       -> '金额'
/// '交易时间'    -> '交易时间'
/// '收/支'      -> '收支'
/// '收/支方式'   -> '收支方式'
/// ```
///
/// 归一化规则：
/// 1. 去掉 BOM
/// 2. 去掉空白（含全角空格）
/// 3. 去掉标点噪声：`( ) （ ） / \ : _ - — － · ・`
/// 4. 去掉「人民币」
/// 5. 去掉结尾的「元 / 圆」
///
/// 参考 `MageGojo/lizhang` 的 `_normalizeHeader`，并补齐全角括号与
/// 结尾「元」的两种写法（`金额(元)` / `金额（元）`）。
class HeaderNormalizer {
  HeaderNormalizer._();

  static final RegExp _noise =
      RegExp(r'[\s\u3000()（）/\\:_\-—－–·・．.]');

  static final RegExp _trailingCurrencyUnit = RegExp(r'[元圆]$');

  /// 归一化单个表头单元格。
  static String normalize(String raw) {
    var s = raw.replaceAll('\uFEFF', '');
    s = s.replaceAll(_noise, '');
    s = s.replaceAll('人民币', '');
    if (s.length > 1) {
      s = s.replaceFirst(_trailingCurrencyUnit, '');
    }
    return s.trim();
  }

  /// 归一化整行表头。
  static List<String> normalizeRow(List<String> rawHeaders) =>
      rawHeaders.map(normalize).toList(growable: false);
}
