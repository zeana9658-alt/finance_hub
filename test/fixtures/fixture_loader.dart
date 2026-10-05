import 'dart:io';
import 'dart:typed_data';

/// 测试夹具加载器。
///
/// `flutter test` 的工作目录是项目根目录，因此直接用相对路径即可。
///
/// ⚠️ 所有夹具数据均为**虚构**：商户名以「示例」开头，单号以 `TEST-` 开头。
/// 见 docs/TESTING.md §5。
class FixtureLoader {
  FixtureLoader._();

  static const String dir = 'test/fixtures';

  /// 读取文本夹具（按 UTF-8）。
  static String text(String name) => File('$dir/$name').readAsStringSync();

  /// 读取字节夹具（GBK 等非 UTF-8 场景必须用这个）。
  static Uint8List bytes(String name) => File('$dir/$name').readAsBytesSync();

  /// 夹具是否存在（用于给出更友好的失败信息）。
  static bool exists(String name) => File('$dir/$name').existsSync();
}
