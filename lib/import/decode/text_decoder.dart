import 'dart:convert';

import 'package:charset/charset.dart' as charset;
import 'package:finance_hub/core/errors/app_error.dart';

/// 解码结果：文本 + 实际使用的编码（便于排查与展示）。
class DecodedText {
  const DecodedText(this.text, this.encoding);

  final String text;

  /// 实际生效的编码名，如 `utf-8-sig` / `gbk` / `latin1`。
  final String encoding;

  @override
  String toString() => 'DecodedText(${text.length} 字符, $encoding)';
}

/// 账单文本解码器 —— 全项目最大的技术坑之一。
///
/// **支付宝网页版导出的 CSV 默认是 GBK 编码**，直接用 UTF-8 解会得到乱码。
/// 微信导出通常是 UTF-8（可能带 BOM）。
///
/// 回退链（见 docs/IMPORT_FORMATS.md §2）：
/// ```
/// utf-8-sig → utf-8 → gb18030 → gbk → latin1(兜底)
/// ```
///
/// **关键设计**：判定「解码成功」不能只看「是否抛异常」——
/// `latin1` 对任何字节都不抛异常。因此每一步都要求解码结果
/// 通过 [_looksLikeBill] 的表头特征校验。
///
/// 选型说明：用纯 Dart 的 `charset` 包，Android 与 Windows 行为一致。
/// 不用 `charset_converter`（平台通道，Windows 不可靠），
/// 不用 `fast_gbk`（SDK 约束 `<3.0.0`，Dart 3 无法解析）。
class TextDecoder {
  TextDecoder._();

  /// 回退链（展示用）。
  static const List<String> candidateEncodings = <String>[
    'utf-8-sig',
    'utf-8',
    'gb18030',
    'gbk',
    'latin1',
  ];

  /// 账单文件里几乎必然出现的表头关键词。
  static const List<String> _billMarkers = <String>[
    '交易时间',
    '交易创建时间',
    '交易对方',
    '交易单号',
    '交易订单号',
    '金额',
    '收/支',
    '商品',
  ];

  static const List<int> _utf8Bom = <int>[0xEF, 0xBB, 0xBF];

  /// 解码字节内容。
  ///
  /// 永远不抛异常（除了空输入），保证「畸形文件不崩溃」。
  static DecodedText decode(List<int> bytes) {
    if (bytes.isEmpty) {
      return const DecodedText('', 'empty');
    }

    // ① UTF-8 BOM（微信 CSV 常见）
    if (_startsWithBom(bytes)) {
      final body = bytes.sublist(_utf8Bom.length);
      try {
        return DecodedText(utf8.decode(body), 'utf-8-sig');
      } on FormatException {
        // BOM 存在但内容不是合法 UTF-8，继续往下试
      }
    }

    // ② UTF-8
    final utf8Text = _tryUtf8(bytes);
    if (utf8Text != null && _looksLikeBill(utf8Text)) {
      return DecodedText(utf8Text, 'utf-8');
    }

    // ③ GBK / GB18030
    final gbkText = _tryGbk(bytes);
    if (gbkText != null && _looksLikeBill(gbkText)) {
      return DecodedText(gbkText, 'gbk');
    }

    // ④ 放宽校验：能解出可读文本就用（可能是极简账单，没有标准表头）
    if (utf8Text != null) {
      return DecodedText(utf8Text, 'utf-8');
    }
    if (gbkText != null) {
      return DecodedText(gbkText, 'gbk');
    }

    // ⑤ 最后兜底：latin1 保证不抛异常，让上层去报「无法识别表头」
    return DecodedText(
      latin1.decode(bytes, allowInvalid: true),
      'latin1',
    );
  }

  /// 解码并断言拿到了可识别的账单文本。
  ///
  /// 用于需要明确失败的场景。
  static DecodedText decodeStrict(List<int> bytes) {
    final decoded = decode(bytes);
    if (decoded.text.trim().isEmpty) {
      throw const DecodeException('文件内容为空');
    }
    if (decoded.encoding == 'latin1') {
      throw const DecodeException(
        '无法确定文件编码',
        detail: '尝试过 utf-8-sig / utf-8 / gbk 均未得到可识别的账单文本',
      );
    }
    return decoded;
  }

  static bool _startsWithBom(List<int> bytes) {
    if (bytes.length < _utf8Bom.length) {
      return false;
    }
    for (var i = 0; i < _utf8Bom.length; i++) {
      if (bytes[i] != _utf8Bom[i]) {
        return false;
      }
    }
    return true;
  }

  static String? _tryUtf8(List<int> bytes) {
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return null;
    }
  }

  static String? _tryGbk(List<int> bytes) {
    try {
      return charset.gbk.decode(bytes);
    } on Object {
      return null;
    }
  }

  /// 判断解码结果是否「看起来像账单」。
  static bool _looksLikeBill(String text) {
    final sample = text.length > 4000 ? text.substring(0, 4000) : text;
    for (final marker in _billMarkers) {
      if (sample.contains(marker)) {
        return true;
      }
    }
    return false;
  }
}
