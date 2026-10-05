import 'package:finance_hub/domain/enums/category_source.dart';

/// 一次「分类结果落库」的更新指令。
///
/// 用于批量重分类：把引擎算出的分类写回交易，并记录**分类来源**，
/// 这样下次重跑时能正确区分「系统算的」与「用户定的」。
class CategoryUpdate {
  const CategoryUpdate({
    required this.transactionId,
    required this.source,
    this.categoryId,
    this.subcategoryId,
  });

  final int transactionId;

  final int? categoryId;
  final int? subcategoryId;

  /// 这次分类的来源。重跑时写入的是 `keyword` / `merchantMemory` /
  /// `platform` / `fallback`，**绝不会是 `manual`**。
  final CategorySource source;

  @override
  String toString() =>
      'CategoryUpdate(#$transactionId → cat=$categoryId/sub=$subcategoryId, ${source.code})';
}
