import 'dart:convert';

import 'package:crypto/crypto.dart';

/// 计算 SHA-1 十六进制摘要。
///
/// 用于交易去重指纹（见 docs/DATABASE.md §3）。
String sha1Hex(String input) => sha1.convert(utf8.encode(input)).toString();

/// 计算字节内容的 SHA-1，用于识别「同一个文件是否已经导入过」。
String sha1HexOfBytes(List<int> bytes) => sha1.convert(bytes).toString();
