import 'package:finance_hub/domain/entities/category_update.dart';
import 'package:finance_hub/domain/entities/normalized_transaction.dart';
import 'package:finance_hub/domain/services/duplicate_detector.dart';

/// 交易仓储接口（由 data 层实现）。
///
/// domain 层只依赖这个抽象，因此分类/聚合/导入等业务逻辑
/// 可以在**没有数据库**的情况下单元测试。
abstract class TransactionRepository {
  /// 批量写入。使用 `INSERT OR IGNORE` + 部分唯一索引兜底去重。
  ///
  /// 返回**实际新增**的行数（被唯一索引拦下的不计入）。
  Future<int> insertAll(List<NormalizedTransaction> transactions);

  /// 取指定时间范围内已存在的 `unique_key` 集合（用于强重复判定）。
  Future<Set<String>> existingUniqueKeys({
    required int fromMillis,
    required int toMillis,
  });

  /// 取指定时间范围内已有交易的探针（用于跨平台疑似重复提示）。
  ///
  /// 只查导入时间跨度内的数据，不必全表加载。
  Future<List<TransactionProbe>> existingProbes({
    required int fromMillis,
    required int toMillis,
  });

  /// 按时间区间查询（不含已删除）。
  Future<List<NormalizedTransaction>> findByRange({
    required int fromMillis,
    required int toMillis,
    int? limit,
    int offset = 0,
  });

  /// 全部未删除交易（**重新分类**用）。
  Future<List<NormalizedTransaction>> findAll();

  /// 交易总数。
  Future<int> count({bool includeDeleted = false});

  /// 软删除（写 `deleted_at`，可撤销）。
  Future<void> softDelete(int id);

  /// 撤销软删除。
  Future<void> restore(int id);

  /// 更新分类（会同时把 `category_source` 设为 `manual`，
  /// 从而在后续「重新分类」时被保护，见 brief 第 11 条）。
  Future<void> updateCategory({
    required int id,
    required int? categoryId,
    required int? subcategoryId,
    required bool markAsManual,
  });

  /// 批量写回分类结果（重新分类用）。
  ///
  /// 返回实际被改写的行数。只在真正有变化时才应传入，
  /// 避免无谓的写放大。
  Future<int> applyCategoryUpdates(List<CategoryUpdate> updates);
}
