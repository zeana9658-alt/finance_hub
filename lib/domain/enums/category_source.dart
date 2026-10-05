/// 分类的来源 —— 决定该分类是否受「重新分类」保护。
///
/// 与数据库 `transactions.category_source` 的 CHECK 约束取值一一对应。
///
/// brief 第 11 条硬要求：重新分类历史账单时**必须保留用户手动修改的分类**。
/// 实现方式就是：重跑时跳过 `categorySource == manual` 的行。
///
/// 优先级顺序（高 → 低）见 [priority]。
enum CategorySource {
  manual('manual', '手动指定', 0),
  merchantMemory('merchant_memory', '商户记忆', 1),
  platform('platform', '平台原始分类', 2),
  keyword('keyword', '关键词规则', 3),
  ai('ai', 'AI 分类', 4),
  fallback('fallback', '未分类', 5);

  const CategorySource(this.code, this.label, this.priority);

  final String code;
  final String label;

  /// 数值越小优先级越高。分类引擎按此顺序尝试。
  final int priority;

  /// 用户手动指定的分类 —— 重新分类时必须跳过，不得覆盖。
  bool get isUserLocked => this == CategorySource.manual;

  /// 是否由系统自动产生（可被重新分类覆盖）。
  bool get isAutoAssigned => !isUserLocked;

  static CategorySource? fromCode(String? code) {
    if (code == null) {
      return null;
    }
    for (final value in CategorySource.values) {
      if (value.code == code) {
        return value;
      }
    }
    return null;
  }

  @override
  String toString() => label;
}
