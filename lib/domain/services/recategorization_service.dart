import 'package:finance_hub/domain/entities/category_update.dart';
import 'package:finance_hub/domain/repositories/transaction_repository.dart';
import 'package:finance_hub/domain/services/categorization_engine.dart';

/// 重跑分类的结果。
class RecategorizationResult {
  const RecategorizationResult({
    required this.totalTransactions,
    required this.changed,
    required this.skippedManual,
    required this.stillUncategorized,
    required this.elapsed,
  });

  /// 库里未删除的交易总数。
  final int totalTransactions;

  /// 实际被改写分类的条数。
  final int changed;

  /// 因为**用户手动指定过分类**而跳过的条数（brief 第 11 条的保护）。
  final int skippedManual;

  /// 重跑后仍然没有分类的条数（没有规则命中）。
  final int stillUncategorized;

  final Duration elapsed;

  @override
  String toString() =>
      'RecategorizationResult(共 $totalTransactions 条，改写 $changed，'
      '跳过手动 $skippedManual，仍未分类 $stillUncategorized，耗时 ${elapsed.inMilliseconds}ms)';
}

/// 重新分类历史账单 —— brief 第 11 条的核心要求。
///
/// 设计要点：
/// 1. **纯编排**：真正的判断在 [CategorizationEngine]（纯函数），落库在
///    [TransactionRepository]，本类只负责遍历与统计。
/// 2. **绝不覆盖手动分类**：`categorySource == manual` 的交易直接跳过。
/// 3. **只写变化行**：分类没变的交易不产生 UPDATE，避免无谓写放大。
class RecategorizationService {
  const RecategorizationService({
    required this.repository,
    required this.engine,
  });

  final TransactionRepository repository;
  final CategorizationEngine engine;

  /// 执行重跑。
  ///
  /// [onProgress] 会以 `(已完成, 总数)` 回调，用于界面展示进度。
  Future<RecategorizationResult> run({
    void Function(int done, int total)? onProgress,
  }) async {
    final stopwatch = Stopwatch()..start();

    final all = await repository.findAll();
    final updates = <CategoryUpdate>[];
    var skippedManual = 0;
    var stillUncategorized = 0;

    for (var i = 0; i < all.length; i++) {
      final transaction = all[i];
      final id = transaction.id;
      if (id == null) {
        continue;
      }

      // ★ 保护用户的手动分类：这是 brief 第 11 条的硬要求
      if (transaction.isCategoryLocked) {
        skippedManual++;
        continue;
      }

      final assignment = engine.categorize(transaction);

      if (!assignment.isAssigned) {
        stillUncategorized++;
      }

      // 分类结果与现状完全一致 → 不需要写库
      final unchanged = assignment.categoryId == transaction.categoryId &&
          assignment.subcategoryId == transaction.subcategoryId &&
          assignment.source == transaction.categorySource;
      if (unchanged) {
        continue;
      }

      updates.add(
        CategoryUpdate(
          transactionId: id,
          categoryId: assignment.categoryId,
          subcategoryId: assignment.subcategoryId,
          source: assignment.source,
        ),
      );

      if (onProgress != null && i % 200 == 0) {
        onProgress(i + 1, all.length);
      }
    }

    final changed = await repository.applyCategoryUpdates(updates);

    if (onProgress != null) {
      onProgress(all.length, all.length);
    }

    stopwatch.stop();
    return RecategorizationResult(
      totalTransactions: all.length,
      changed: changed,
      skippedManual: skippedManual,
      stillUncategorized: stillUncategorized,
      elapsed: stopwatch.elapsed,
    );
  }
}
